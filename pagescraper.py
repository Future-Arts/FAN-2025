'''
Functions for webscraper functionality that involves scraping a specific,
individual page. Should only EVER be deployed by scraping_manager, not
designed to interface directly with user or any non-managed interface
'''

import requests
from bs4 import BeautifulSoup
import json
import dotenv
from scrapercfg import IMG_FILETYPES, TEXT_FILETYPES, AUDIO_FILETYPES, VIDEO_FILETYPES
from soupsorter import extract_images

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

    extracted_data = dict()

    # Extract images
    def get_highest_resolution_image(img_tag):
        # Function to get the highest resolution image from a tag
        sources = img_tag.find_all('source')
        if sources:
            # If there are multiple sources, choose the one with the highest resolution
            highest_res = max(sources, key=lambda s: int(s.get('data-res', '0')))
            return highest_res.get('srcset') or highest_res.get('src')
        return img_tag.get('src') or img_tag.get('data-src') or img_tag.get('data-lazy-src')

    for img in soup.find_all(['img', 'picture']):
        img_url = get_highest_resolution_image(img)
        if img_url:
            extracted_data.setdefault('images', []).append(
                {
                    "parent_element": img.parent.name,
                    "element": img.name,
                    "link_text": img.get('alt', ''),
                    "url": img_url
                }
            )


    # Extract text (paragraphs as an example)
    for p in soup.find_all('p'):
        media['text'].append({
            "parent_element": p.parent.name,
            "element": p.name,
            "content": p.get_text(strip=True)
        })

    # Extract audio (example: <audio> tags)
    for audio in soup.find_all('audio'):
        media['audio'].append({
            "parent_element": audio.parent.name,
            "element": audio.name,
            "url": audio.get('src', '')
        })

    # Extract other file links (pdf, etc.)
    for link in soup.find_all('a', href=True):
        href = link['href']
        if href.endswith('.pdf') or href.endswith('.zip'):
            media['misc_files'].append({
                "parent_element": link.parent.name,
                "element": link.name,
                "link_text": link.get_text(strip=True),
                "url": href
            })

        # Internal/external link classification
        if url in href or href.startswith('/'):
            links['internal'].append({
                "link_text": link.get_text(strip=True),
                "url": href
            })
        else:
            links['external'].append({
                "link_text": link.get_text(strip=True),
                "url": href
            })

    # Package the scraped data into a JSON object
    data = {
        "url": url,
        "media": media,
        "links": links
    }

    return json.dumps(data, indent=4)

# Example usage
if __name__ == "__main__":
    # This URL would be passed to the Lambda function
    example_url = input("Enter the URL to scrape: ")
    scraped_data = scrape_page(example_url)
    print(scraped_data)