
'''
Functions for webscraper functionality that involves scraping a specific,
individual page. not designed to interface directly with user 
or any non-managed interface
'''

import requests
from bs4 import BeautifulSoup
import json
from collections import defaultdict
from urllib.parse import urlparse, urljoin
from functools import reduce
import boto3
# new
import validators

# Initialize S3 client
s3 = boto3.client('s3')

UNWANTED_TAGS = ['head', 'button', 'form', 'input', 'script', 'style', 'link']
UNWANTED_ENCLOSING_TAGS = []
# endregion

# region image collection settings
MIN_IMG_DIMENSIONS = {
    'width' : 64,
    'height' : 64,
}



# region helper functions
def get_link_type(href, url):
    if urlparse(url).netloc == urlparse(urljoin(url, href)).netloc:
        return 'internal'
    return 'external'


def link_reduce(url, acc, link_data):
    '''
    The 'ancestor tag list' is a list of the link's parents all the way up to the root of the document
    It is intended to help identify common patterns in link structures and what tags are important
    By identifying common patterns, we can better understand the structure of pages and optimize our scraping strategy
    '''
    href = link_data['href']
    acc[get_link_type(href, url)][href]

    # commented out the following line
    # acc[get_link_type(href)][href].append({
    #     'tag': str(link_data['tag']),
    #     'ancestor_tags': [parent.name for parent in link_data['tag'].parents]
    # })
    return acc

def clean_soup(soup):
    '''
    Cleans the soup object by removing unwanted tags and attributes
    '''
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
    '''
    Formats the soup for looking at in output json
    '''
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

# endregion helper functions

def fetch_page(url : str) -> object:
    '''
    Fetches the content of a webpage and returns a BeautifulSoup object
    '''
    try:
        response = requests.get(url)
        response.raise_for_status()  # Raise error for bad status codes
        soup = BeautifulSoup(response.text, 'html.parser')
        test = ' '.join(soup.stripped_strings)
        return soup
    except Exception as e:
        return {"error": f"Failed to fetch {url}: {e}"}

def scrape_links(url, soup : object) -> dict:
    '''
    Extracts all links from the BeautifulSoup object and categorizes them as internal or external
    Has some side effects, such as removing links that start with '#' or link tags that don't have href attributes
    '''
    for link_element in soup.find_all('a', href=lambda href: not href or href.startswith('#')):
        link_element.decompose()
    links = reduce(
        lambda acc, link_data: link_reduce(url, acc, link_data),
        [{'tag' : tag, 'href' : tag.get('href')}for tag in soup.find_all('a')],
        {'internal': defaultdict(list), 'external': defaultdict(list)})
    return links

def scrape_images(soup : object) -> list:
    '''
    Extracts all images from the BeautifulSoup object and returns a list of image URLs
    TODO: Implement image dimension filtering
    TODO: Implement image deduplication
    TODO: Implement image format filtering
    '''
    images = [{'src': img.get('src')} for img in soup.find_all('img', src=True)]
    return images

# Function to scrape a single webpage
def scrape_page(url : str) -> object:
    soup = fetch_page(url)
    links = scrape_links(url, soup)
    # images = scrape_images(soup)
    clean_soup(soup)

    linkVisited = set()
    linkVisited.add(url)


    final_result = {}
    final_result[url] = {
        'links'     : links,
        # 'images'    : images,
        'text'      : list(soup.stripped_strings),
        # 'html'      : format_soup(soup)
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
            # images = scrape_images(soup)
            if "contact" in link or "about" in link:
                links = scrape_links(url, soup)
                final_result[link] = {
                    'links'     : links,
                    'text'      : list(soup.stripped_strings),
                    # 'images'    : images
                }
                
            else :
                # check if page may not have any text
                if soup and hasattr(soup, 'stripped_strings') and soup.stripped_strings:
                    text_data = list(soup.stripped_strings)
                else:
                    text_data = ''

                final_result[link] = {
                    'text'      : text_data,
                }

            linkVisited.add(url+link)
            numInternalLinksToscrape -= 1
    print(final_result)
    return final_result

# what if the data is large => do different way
def storeToS3_artistScrapedData(data, row_id):
    bucket_name = 'artist-scraped-data'
    fileName = 'artist-scraped-data.json'

    # Add row_id at the top of the data
    structured_data = {
        "rowId": row_id,
        "data": data
    }

    uploadByteStream = bytes(json.dumps(structured_data, indent=4).encode('UTF-8'))

    # Store the data in S3
    s3.put_object(Bucket=bucket_name, Key=fileName, Body=uploadByteStream)

    print(f'Data stored in S3 with rowId: {row_id}')

def storeToS3_analyzedData(errorData, row_id):
    bucket_name = 'artists-analyzed-data'
    fileName = 'artists-analyzed-data.json'

    # Add row_id at the top of the data
    structured_data = {
        "rowId": row_id,
        "errorData": errorData,
    }
    # print(f'Data stored in S3 structure: {structured_data}')

    uploadByteStream = bytes(json.dumps(structured_data, indent=4).encode('UTF-8'))
    # Store the data in S3
    s3.put_object(Bucket=bucket_name, Key=fileName, Body=uploadByteStream)



def lambda_handler(event, context):
    print("Received event:", json.dumps(event)) # degug
    try:
        # Ensure the event has a body
        if 'url' not in event:
            return {'statusCode': 400, 'body': json.dumps('Error: Request url is missing')}
        if 'rowId' not in event:
            return {'statusCode': 400, 'body': json.dumps('Error: Request rowId is missing')}

        url = event.get('url')
        row_id  = event.get('rowId')

        if not validators.url(url):
            storeToS3_analyzedData("Invalid URL format.", row_id)
            return {"statusCode": 400, "body": "Invalid URL format."}

        # result = scrape_page('https://mikeheavers.com/')
        result = scrape_page(url)

        # Store the scraped data in S3
        storeToS3_artistScrapedData(result, row_id)

        return {
            'statusCode': 200,
            'body': json.dumps('Scrape data completed!')
        }
    
    except Exception as e:
        if 'rowId' in event:
            row_id = event.get('rowId')
            storeToS3_analyzedData(str(e), row_id)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

