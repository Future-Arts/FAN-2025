"""
Functions for webscraper functionality that involves scraping a specific,
individual page. Modified to store sitemap data in DynamoDB for dashboard integration.
"""

import requests
from bs4 import BeautifulSoup
import json
import os
import time
from collections import defaultdict
from urllib.parse import urlparse, urljoin
from functools import reduce
import boto3

# Initialize AWS clients
s3 = boto3.client('s3')
sqs = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')

UNWANTED_TAGS = ['head', 'button', 'form', 'input', 'script', 'style', 'link']
UNWANTED_ENCLOSING_TAGS = []

# region helper functions
def get_link_type(href, url):
    if urlparse(url).netloc == urlparse(urljoin(url, href)).netloc:
        return 'internal'
    return 'external'

def link_reduce(url, acc, link_data):
    """
    The 'ancestor tag list' is a list of the link's parents all the way up to the root of the document
    It is intended to help identify common patterns in link structures and what tags are important
    By identifying common patterns, we can better understand the structure of pages and optimize our scraping strategy
    """
    href = link_data['href']
    acc[get_link_type(href, url)][href] = []
    return acc

def clean_soup(soup):
    """
    Cleans the soup object by removing unwanted tags and attributes
    """
    tags_to_remove = {'decompose' : [],
                      'unwrap' : []
                     }
    # Remove childless divs
    tags_to_remove['decompose'] += [x for x in soup.find_all('div') if not x.find_all()]
    tags_to_remove['decompose'] += soup.find_all(UNWANTED_TAGS)
    tags_to_remove['unwrap'] += soup.find_all(UNWANTED_ENCLOSING_TAGS)
    for tag in tags_to_remove['decompose']:
        tag.decompose()
    for tag in tags_to_remove['unwrap']:
        if tag.contents:
            tag.unwrap()
        else:
            tag.decompose()

def format_soup(soup) -> str:
    """
    Formats the soup for looking at in output json
    """
    if not hasattr(soup, "name") or soup.name is None:
        text = soup.strip() if isinstance(soup, str) else None
        return text if text else None  # Return text or None if it's empty

    # Process child elements
    children = []
    for child in soup.children:
        child_result = format_soup(child)
        if child_result is not None:  # Ignore empty results
            children.append(child_result)

    # Return a dictionary for this tag, with children if they exist
    return {soup.name: children} if children else {soup.name: None}

def normalize_url(url):
    """Normalize URL by removing trailing slashes and fragments"""
    parsed = urlparse(url)
    normalized = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
    return normalized.rstrip('/')

def extract_sitemap_data(scraping_results, base_url):
    """
    Extract sitemap data from scraping results.
    Returns a dictionary with URLs as keys and lists of found URLs as values.
    """
    sitemap = {}
    base_domain = urlparse(base_url).netloc
    
    for page_url, page_data in scraping_results.items():
        if 'links' not in page_data:
            continue
            
        normalized_page_url = normalize_url(page_url)
        internal_links = []
        
        # Extract internal links
        if 'internal' in page_data['links']:
            for link_href in page_data['links']['internal'].keys():
                # Convert relative URLs to absolute URLs
                absolute_url = urljoin(base_url, link_href)
                normalized_link = normalize_url(absolute_url)
                
                # Only include links from the same domain
                if urlparse(normalized_link).netloc == base_domain:
                    internal_links.append(normalized_link)
        
        # Remove duplicates and sort for consistency
        sitemap[normalized_page_url] = sorted(list(set(internal_links)))
    
    return sitemap

def check_url_exists_in_dynamodb(url, website_domain):
    """
    Check if URL already exists in the DynamoDB sitemap for the domain.
    Returns True if URL exists, False otherwise.
    """
    try:
        table_name = os.environ.get('SITEMAP_TABLE_NAME', 'website-sitemaps')
        table = dynamodb.Table(table_name)
        
        response = table.get_item(
            Key={'website_domain': website_domain}
        )
        
        if 'Item' not in response:
            return False
            
        sitemap = response['Item'].get('sitemap', {})
        return normalize_url(url) in sitemap
        
    except Exception as e:
        print(f'Error checking URL in DynamoDB: {e}')
        return False

def lock_url_in_dynamodb(url, website_domain):
    """
    Create a placeholder entry for the URL to prevent race conditions.
    Returns True if successfully locked, False if already exists.
    """
    try:
        table_name = os.environ.get('SITEMAP_TABLE_NAME', 'website-sitemaps')
        table = dynamodb.Table(table_name)
        normalized_url = normalize_url(url)
        
        # First, try to get existing domain record
        try:
            response = table.get_item(
                Key={'website_domain': website_domain}
            )
            
            if 'Item' in response:
                # Domain record exists, check if URL already exists
                sitemap = response['Item'].get('sitemap', {})
                if normalized_url in sitemap:
                    print(f'URL {normalized_url} already exists in sitemap')
                    return False
                
                # Add URL placeholder to existing sitemap
                sitemap[normalized_url] = []  # Empty list as placeholder
                
                table.update_item(
                    Key={'website_domain': website_domain},
                    UpdateExpression='SET sitemap = :sitemap, last_updated = :timestamp',
                    ExpressionAttributeValues={
                        ':sitemap': sitemap,
                        ':timestamp': int(time.time())
                    }
                )
            else:
                # Create new domain record with URL placeholder
                table.put_item(
                    Item={
                        'website_domain': website_domain,
                        'sitemap': {normalized_url: []},
                        'last_updated': int(time.time())
                    }
                )
                
            print(f'URL {normalized_url} locked in DynamoDB for domain: {website_domain}')
            return True
            
        except Exception as e:
            print(f'Error locking URL in DynamoDB: {e}')
            return False
            
    except Exception as e:
        print(f'Error in lock_url_in_dynamodb: {e}')
        return False

def update_url_sitemap_in_dynamodb(url, discovered_links, website_domain):
    """
    Update the specific URL entry in DynamoDB with discovered internal links.
    """
    try:
        table_name = os.environ.get('SITEMAP_TABLE_NAME', 'website-sitemaps')
        table = dynamodb.Table(table_name)
        normalized_url = normalize_url(url)
        
        # Get current sitemap
        response = table.get_item(
            Key={'website_domain': website_domain}
        )
        
        if 'Item' not in response:
            print(f'Warning: Domain {website_domain} not found when updating URL {normalized_url}')
            return False
            
        sitemap = response['Item'].get('sitemap', {})
        
        # Update the specific URL with discovered links
        sitemap[normalized_url] = discovered_links
        
        # Update the record
        table.update_item(
            Key={'website_domain': website_domain},
            UpdateExpression='SET sitemap = :sitemap, last_updated = :timestamp',
            ExpressionAttributeValues={
                ':sitemap': sitemap,
                ':timestamp': int(time.time())
            }
        )
        
        print(f'Updated sitemap for {normalized_url} with {len(discovered_links)} internal links')
        return True
        
    except Exception as e:
        print(f'Error updating URL sitemap in DynamoDB: {e}')
        return False

def store_sitemap_to_dynamodb(sitemap_data, website_domain):
    """
    Store sitemap data in DynamoDB table.
    Each website gets one record with the sitemap as a JSON object.
    DEPRECATED: Use update_url_sitemap_in_dynamodb for concurrent execution.
    """
    try:
        table_name = os.environ.get('SITEMAP_TABLE_NAME', 'website-sitemaps')
        table = dynamodb.Table(table_name)
        
        # Store the sitemap data
        response = table.put_item(
            Item={
                'website_domain': website_domain,
                'sitemap': sitemap_data,
                'last_updated': int(time.time())
            }
        )
        
        print(f'Sitemap stored in DynamoDB for domain: {website_domain}')
        return response
        
    except Exception as e:
        print(f'Error storing sitemap to DynamoDB: {e}')
        raise

# endregion helper functions

def fetch_page(url: str) -> object:
    """
    Fetches the content of a webpage and returns a BeautifulSoup object
    """
    try:
        response = requests.get(url)
        response.raise_for_status()  # Raise error for bad status codes
        soup = BeautifulSoup(response.text, 'html.parser')
        test = ' '.join(soup.stripped_strings)
        return soup
    except Exception as e:
        return {"error": f"Failed to fetch {url}: {e}"}

def scrape_links(url, soup: object) -> dict:
    """
    Extracts all links from the BeautifulSoup object and categorizes them as internal or external
    Has some side effects, such as removing links that start with '#' or link tags that don't have href attributes
    """
    for link_element in soup.find_all('a', href=lambda href: not href or href.startswith('#')):
        link_element.decompose()
    links = reduce(
        lambda acc, link_data: link_reduce(url, acc, link_data),
        [{'tag': tag, 'href': tag.get('href')} for tag in soup.find_all('a')],
        {'internal': defaultdict(list), 'external': defaultdict(list)})
    return links

def send_urls_to_queue(urls, queue_url):
    """
    Send a list of URLs to the SQS queue for processing by other Lambda instances.
    """
    try:
        if not urls:
            return
            
        messages_sent = 0
        for url in urls:
            message_body = json.dumps({"page_url": url})
            
            response = sqs.send_message(
                QueueUrl=queue_url,
                MessageBody=message_body
            )
            
            if response.get('MessageId'):
                messages_sent += 1
                print(f'Queued URL for processing: {url}')
            else:
                print(f'Failed to queue URL: {url}')
                
        print(f'Successfully queued {messages_sent} URLs out of {len(urls)}')
        return messages_sent
        
    except Exception as e:
        print(f'Error sending URLs to queue: {e}')
        return 0

def scrape_single_page(url: str) -> dict:
    """
    Scrape a single webpage and return its content and links.
    This function processes only ONE URL, not multiple URLs.
    """
    try:
        soup = fetch_page(url)
        if isinstance(soup, dict) and 'error' in soup:
            print(f'Error fetching page {url}: {soup["error"]}')
            return {
                'url': url,
                'links': {'internal': {}, 'external': {}},
                'text': [],
                'error': soup['error']
            }
            
        links = scrape_links(url, soup)
        clean_soup(soup)
        
        result = {
            'url': url,
            'links': links,
            'text': list(soup.stripped_strings),
        }
        
        print(f'Successfully scraped {url}: found {len(links["internal"])} internal links, {len(links["external"])} external links')
        return result
        
    except Exception as e:
        print(f'Error scraping page {url}: {e}')
        return {
            'url': url,
            'links': {'internal': {}, 'external': {}},
            'text': [],
            'error': str(e)
        }

# Function to scrape a single webpage (DEPRECATED - kept for backward compatibility)
def scrape_page(url: str) -> object:
    """
    DEPRECATED: This function is kept for backward compatibility.
    Use scrape_single_page for new concurrent implementation.
    """
    soup = fetch_page(url)
    links = scrape_links(url, soup)
    clean_soup(soup)

    linkVisited = set()
    linkVisited.add(url)

    final_result = {}
    final_result[url] = {
        'links': links,
        'text': list(soup.stripped_strings),
    }

    # not implement
    potential_dublicate = [
        'Close', 'Open', 'Close Menu', 'Open Menu', 'Portfolio', 'view fullsize', 'Next', '0', 'Previous', 'home', 'contacts'
    ]
    
    # new
    numInternalLinksToscrape = 6 if len(links['internal']) > 6 else len(links['internal'])
    while numInternalLinksToscrape > 0:
        for link in links['internal']:
            if numInternalLinksToscrape == 0:
                break
            
            if link in linkVisited or "interview" in link:
                continue

            soup = fetch_page(urljoin(url, link))
            if "contact" in link or "about" in link:
                links = scrape_links(url, soup)
                final_result[link] = {
                    'links': links,
                    'text': list(soup.stripped_strings),
                }
            else:
                # check if page may not have any text
                if soup and hasattr(soup, 'stripped_strings') and soup.stripped_strings:
                    text_data = list(soup.stripped_strings)
                else:
                    text_data = ''

                final_result[link] = {
                    'text': text_data,
                }

            linkVisited.add(link)
            numInternalLinksToscrape -= 1
    print(final_result)
    return final_result

def storeDataToS3(data, page_url):
    bucket_name = 'artist-scraped-data'
    fileName = f'scraped-data-{int(time.time())}.json'

    # Add page_url at the top of the data
    structured_data = {
        "page_url": page_url,
        "timestamp": int(time.time()),
        "data": data
    }

    uploadByteStream = bytes(json.dumps(structured_data, indent=4).encode('UTF-8'))

    # Store the data in S3
    s3.put_object(Bucket=bucket_name, Key=fileName, Body=uploadByteStream)

    print(f'Data stored in S3 for URL: {page_url}')

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))  # debug

    # Process SQS event
    try:
        # Extract message from SQS event
        records = event.get('Records', [])
        if not records:
            return {'statusCode': 400, 'body': json.dumps('Error: No SQS records found')}
        
        # Process the first record (batch_size is set to 1)
        record = records[0]
        message_body = json.loads(record['body'])
        
        # Extract page_url from the message
        page_url = message_body.get('page_url')
        if not page_url:
            return {'statusCode': 400, 'body': json.dumps('Error: page_url is missing from message')}

        # Get environment variables
        queue_url = os.environ.get('URL_QUEUE_URL')
        if not queue_url:
            print('Warning: URL_QUEUE_URL environment variable not set')
            return {'statusCode': 500, 'body': json.dumps('Error: Queue URL not configured')}
            
        # Extract domain for DynamoDB operations
        website_domain = urlparse(page_url).netloc
        
        # STEP 1: Check if URL already exists or lock it
        if check_url_exists_in_dynamodb(page_url, website_domain):
            print(f'URL {page_url} already processed, skipping')
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'URL already processed',
                    'url': page_url,
                    'status': 'skipped'
                })
            }
        
        # STEP 2: Lock the URL to prevent race conditions
        if not lock_url_in_dynamodb(page_url, website_domain):
            print(f'Failed to lock URL {page_url}, another instance may be processing it')
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'URL being processed by another instance',
                    'url': page_url,
                    'status': 'locked'
                })
            }
        
        # STEP 3: Scrape the single page
        print(f'Processing URL: {page_url}')
        scraping_result = scrape_single_page(page_url)
        
        if 'error' in scraping_result:
            print(f'Error scraping {page_url}: {scraping_result["error"]}')
            # Still update DynamoDB to mark as processed (with empty links)
            update_url_sitemap_in_dynamodb(page_url, [], website_domain)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'URL processed with errors',
                    'url': page_url,
                    'error': scraping_result['error'],
                    'status': 'error'
                })
            }
        
        # STEP 4: Extract internal links and normalize them
        internal_links = scraping_result.get('links', {}).get('internal', {})
        base_domain = urlparse(page_url).netloc
        
        discovered_urls = []
        normalized_internal_links = []
        
        for link_href in internal_links.keys():
            # Convert relative URLs to absolute URLs
            absolute_url = urljoin(page_url, link_href)
            normalized_link = normalize_url(absolute_url)
            
            # Only include links from the same domain
            if urlparse(normalized_link).netloc == base_domain:
                normalized_internal_links.append(normalized_link)
                
                # Check if this URL needs to be queued for processing
                if not check_url_exists_in_dynamodb(normalized_link, website_domain):
                    discovered_urls.append(normalized_link)
        
        # STEP 5: Update DynamoDB with discovered internal links
        update_url_sitemap_in_dynamodb(page_url, normalized_internal_links, website_domain)
        
        # STEP 6: Queue new URLs for processing by other Lambda instances
        queued_count = 0
        if discovered_urls:
            print(f'Found {len(discovered_urls)} new URLs to process')
            queued_count = send_urls_to_queue(discovered_urls, queue_url)
        else:
            print('No new URLs found to queue')
        
        # STEP 7: Store full scraping data in S3 (preserve existing functionality)
        legacy_format = {page_url: {
            'links': scraping_result.get('links', {}),
            'text': scraping_result.get('text', [])
        }}
        storeDataToS3(legacy_format, page_url)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'URL processed successfully',
                'url': page_url,
                'website_domain': website_domain,
                'internal_links_found': len(normalized_internal_links),
                'new_urls_queued': queued_count,
                'status': 'completed'
            })
        }
        
    except Exception as e:
        print(f'Error in lambda_handler: {e}')
        import traceback
        traceback.print_exc()
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing request: {str(e)}')
        }
