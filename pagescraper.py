'''
Functions for webscraper functionality that involves scraping a specific,
individual page. not designed to interface directly with user 
or any non-managed interface
'''

import requests
from bs4 import BeautifulSoup
import json
from config import URL, UNWANTED_ENCLOSING_TAGS, UNWANTED_TAGS
from urllib.parse import urlparse, urljoin
from functools import reduce

# region helper functions
def is_internal_link(href, base_url):
    if href.startswith('/') or href.startswith('#'):
        return True
    return False
def link_reduce(acc, a):
    # Ignore links to page HTML elements and <a> tags with no href
    if not (href := a.get('href')) or href.startswith("#"):
        return acc
    name = a.get('title') or a.get('aria-label') or ''
    link_entry  ={
        'name'  : name,
        'text'  : a.get_text() or '',
        'href'  : href
    }
    acc[['external', 'internal'][int(is_internal_link(href))]].append(link_entry)
    return acc
def clean_soup(soup):
    '''
    Cleans the soup object by removing unwanted tags and attributes
    '''
    # Remove childless divs
    for div in [x for x in soup.find_all('div') if len(div.get_children()) == 0]:
        div.decompose()
    # Remove unwanted tags
    for tag in soup.find_all(UNWANTED_TAGS):
        tag.decompose()
    for tag in soup.find_all(UNWANTED_ENCLOSING_TAGS):
        tag.unwrap()

# endregion helper functions


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
    a_tags = soup.find_all('a')
    links = reduce(link_reduce, a_tags, {'internal': [], 'external': []})

    # extract all the links on the page before further processing
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