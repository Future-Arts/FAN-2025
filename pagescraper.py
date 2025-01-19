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
    # region helper functions
    def is_internal_link(href, base_url):
        parsed_href = urlparse(href)
        parsed_base = urlparse(base_url)
        return parsed_href.netloc == '' or parsed_href.netloc == parsed_base.netloc
    def link_reduce(acc, a):
        # Ignore links to page HTML elements and <a> tags with no href
        if not (href := a.get('href')) or href.startswith("#"):
            return acc
        link_entry  ={
            
            'title' : a.get('title'),
            'text'  : a.get_text(),
            'url'   : urljoin(url, href)
        }
        acc[['internal', 'external'][int(is_internal_link(href, url))]].append(href)
        return acc
    # endregion helper functions
    try:
        # Fetch the webpage
        response = requests.get(url)
        response.raise_for_status()  # Raise error for bad status codes
        soup = BeautifulSoup(response.content, 'html.parser')
    except Exception as e:
        return {"error": f"Failed to scrape {url}: {e}"}
    # extract all the links on the page
    def serialize(element):
        if not (tag := element.name):
            return element
        return {  
            'tag'           : element.name,
            'attributes'    : element.attrs,
            'children'      : [el for el in element.children if el.name not in UNWANTED_ENCLOSING_TAGS],
        }
    serialized_soup = serialize(soup.body)
    with open("test.html", "w", encoding="utf-8") as file:
        file.write(str(serialized_soup))
    print('break') 



# Example usage
if __name__ == "__main__":
    scraped_data = scrape_page(URL)
    print(scraped_data)