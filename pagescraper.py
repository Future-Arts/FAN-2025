'''
Functions for webscraper functionality that involves scraping a specific,
individual page. not designed to interface directly with user 
or any non-managed interface
'''

import requests
from bs4 import BeautifulSoup
import json
from collections import defaultdict
from config import URL, UNWANTED_ENCLOSING_TAGS, UNWANTED_TAGS
from urllib.parse import urlparse, urljoin
from functools import reduce

# region helper functions
def get_link_type(href):
    if urlparse(URL).netloc == urlparse(urljoin(URL, href)).netloc:
        return 'internal'
    return 'external'

def link_reduce(acc, link_data):
    '''
    The 'ancestor tag list' is a list of the link's parents all the way up to the root of the document
    It is intended to help identify common patterns in link structures and what tags are important
    By identifying common patterns, we can better understand the structure of pages and optimize our scraping strategy
    '''
    href = link_data['href']
    acc[get_link_type(href)][href].append({
        'tag': str(link_data['tag']),
        'ancestor_tags': [parent.name for parent in link_data['tag'].parents]
    })
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

def scrape_links(soup : object) -> dict:
    '''
    Extracts all links from the BeautifulSoup object and categorizes them as internal or external
    Has some side effects, such as removing links that start with '#' or link tags that don't have href attributes
    '''
    for link_element in soup.find_all('a', href=lambda href: not href or href.startswith('#')):
        link_element.decompose()
    links = reduce(
        link_reduce,
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
    images = [{'src': img.get('src'),
               'alt': img.get('alt') or 'No alt text'
              } for img in soup.find_all('img', src=True)
             ]
    return images

# Function to scrape a single webpage
def scrape_page(url : str) -> object:
    soup = fetch_page(url)
    links = scrape_links(soup)
    images = scrape_images(soup)
    clean_soup(soup)

    results = {
        'url'       : url,
        'links'     : links,
        'images'    : images,
        'text'      : list(soup.stripped_strings),
        'html'      : format_soup(soup)
    }
    with open("output.json", "w", encoding="utf-8") as file:
        json.dump(results, file, ensure_ascii=False, indent=4)

# Example usage
if __name__ == "__main__":
    scrape_page(URL)
