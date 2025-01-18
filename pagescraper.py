'''
Functions for webscraper functionality that involves scraping a specific,
individual page. not designed to interface directly with user 
or any non-managed interface
'''

import requests
from bs4 import BeautifulSoup
import json
from config import URL, UNWANTED_TAGS
from urllib.parse import urlparse, urljoin
from functools import reduce

# Function to scrape a single webpage
def scrape_page(url : str) -> object:
    '''
    Entry point for the page scraper. Should be called by the scraping manager
    when the process is created

    Args:
        url (string): the url of the specific page to be scraped

    Returns:
        Formatted JSON object containing scraped data
    TODO: explain JSON object format here
    '''
    try:
        # Fetch the webpage
        response = requests.get(url)
        response.raise_for_status()  # Raise error for bad status codes
        soup = BeautifulSoup(response.content, 'html.parser')
    except Exception as e:
        return {"error": f"Failed to scrape {url}: {e}"}
    
    domain = urlparse(url).netloc
    # extract all the links on the page
    links_on_page = soup.find_all('a')
    def link_reduce(acc, a):
        href = a.get('href')
        if not href:
            return acc
        if href.startswith("#"):
            # Ignore internal page links
            return acc
        full_url = urljoin(url, href)  # Resolve relative URLs to absolute
        parsed_url = urlparse(full_url)
        if href.startswith("//"):
            # Protocol-relative external link
            '''
             classification = 'external'
            acc["external"].append(
                {
                    'title': a.get('title'),
                    'text': a.get_text(),
                    'url': full_url
                
                }'''
            acc['external'].append(full_url)
        elif href.startswith("/"):
            # Absolute path within the domain
            acc["internal"].append(full_url)
        elif parsed_url.netloc and parsed_url.netloc != domain:
            # Full URL pointing to an external domain
            acc["external"].append(full_url)
        else:
            # Relative path or fragment (internal link)
            acc["internal"].append(full_url)
        return acc
        
    sorted_links = reduce(link_reduce, links_on_page, {'internal': [], 'external': []})
    # now that we have all the links, we can remove them from the soup
    # by replacing them with their text to remove hyperlinks
    for link in links_on_page:
        link.replaceWith(link.get_text())
    # remove all style tags (not really useful for ai analysis)
    for tag in soup.find_all(['b', 'i', 'u', 'strong', 'em', 'span']):
        tag.unwrap()
    for named_div in [x for x in soup.find_all('div') if x.get('title')]:
        print(named_div.get('title'))
        div_title = named_div.get('title')
        named_div.replaceWith(soup.new_tag('div', title=div_title))
        soup.prettify()
    with open("test.html", "w", encoding="utf-8") as file:
        file.write(str(soup))
    print('break') 



# Example usage
if __name__ == "__main__":
    scraped_data = scrape_page(URL)
    print(scraped_data)