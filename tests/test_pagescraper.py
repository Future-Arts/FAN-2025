import json
import pytest
from collections import defaultdict
from bs4 import BeautifulSoup
from unittest.mock import patch, MagicMock
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../src')))
import pagescraper

def mock_response(content, status_code=200):
    """Creates a mock response object with the given HTML content."""
    mock_resp = MagicMock()
    mock_resp.status_code = status_code
    mock_resp.text = content
    return mock_resp

@patch('pagescraper.requests.get')
def test_fetch_page(mock_get):
    """Test that fetch_page correctly fetches and parses HTML."""
    mock_get.return_value = mock_response('<html><body><h1>Test</h1></body></html>')
    soup = pagescraper.fetch_page('https://example.com')
    assert isinstance(soup, BeautifulSoup)
    assert soup.find('h1').text == 'Test'

@patch('pagescraper.requests.get')
def test_fetch_page_failure(mock_get):
    """Test fetch_page when the request fails."""
    mock_get.side_effect = Exception("Failed to fetch")
    result = pagescraper.fetch_page('https://example.com')
    assert 'error' in result

def test_get_link_type():
    """Test detection of internal and external links."""
    assert pagescraper.get_link_type("/internal") == "internal"
    assert pagescraper.get_link_type("https://external.com/page") == "external"

def test_link_reduce():
    """Test the reduction function for organizing links."""
    html = '<html><body><a href="/test">Test</a></body></html>'
    soup = BeautifulSoup(html, 'html.parser')
    tag = soup.find('a')
    link_data = {'tag': tag, 'href': tag.get('href')}
    acc = {'internal': defaultdict(list), 'external': defaultdict(list)}
    acc = pagescraper.link_reduce(acc, link_data)
    assert '/test' in acc['internal']
    assert len(acc['internal']['/test']) == 1

def test_link_reduce_multiple():
    """Test that link_reduce accumulates multiple entries for the same link."""
    html = '<html><body><a href="/test">Test1</a><a href="/test">Test2</a></body></html>'
    soup = BeautifulSoup(html, 'html.parser')
    tags = soup.find_all('a')
    acc = {'internal': defaultdict(list), 'external': defaultdict(list)}
    for tag in tags:
        link_data = {'tag': tag, 'href': tag.get('href')}
        acc = pagescraper.link_reduce(acc, link_data)
    # Expect two entries for the same internal link
    assert len(acc['internal']['/test']) == 2

def test_scrape_links():
    """Test scraping of internal and external links."""
    html = '''<html><body>
                <a href="/internal">Internal</a>
                <a href="https://external.com">External</a>
              </body></html>'''
    soup = BeautifulSoup(html, 'html.parser')
    links = pagescraper.scrape_links(soup)
    assert 'internal' in links
    assert 'external' in links
    assert '/internal' in links['internal']
    assert 'https://external.com' in links['external']

def test_scrape_links_empty():
    """Test scraping when no links are present."""
    html = '<html><body></body></html>'
    soup = BeautifulSoup(html, 'html.parser')
    links = pagescraper.scrape_links(soup)
    # Check that keys 'internal' and 'external' exist and have no links
    assert isinstance(links, dict)
    assert 'internal' in links and 'external' in links
    assert len(links['internal']) == 0
    assert len(links['external']) == 0

def test_scrape_images():
    """Test image extraction without dimension filtering."""
    html = '''<html><body>
                <img src="image1.jpg" alt="Image One" width="100" height="100">
                <img src="image2.png" width="50" height="50">
                <img src="image3.gif" alt="Missing Source">
              </body></html>'''
    soup = BeautifulSoup(html, 'html.parser')
    images = pagescraper.scrape_images(soup)
    # Expecting 3 images because no filtering is implemented
    assert len(images) == 3
    assert images[0]['src'] == 'image1.jpg'
    assert images[0]['alt'] == 'Image One'
    assert images[1]['src'] == 'image2.png'
    assert images[1]['alt'] == 'No alt text'
    assert images[2]['src'] == 'image3.gif'
    assert images[2]['alt'] == 'Missing Source'

def test_clean_soup():
    """Test unwanted tag removal."""
    html = '<html><body><script>alert("Hi");</script><p>Text</p></body></html>'
    soup = BeautifulSoup(html, 'html.parser')
    pagescraper.clean_soup(soup)
    assert soup.find('script') is None
    assert soup.find('p').text == 'Text'

def test_format_soup():
    """Test simple formatting of a BeautifulSoup tag."""
    html = '<p>Test</p>'
    soup = BeautifulSoup(html, 'html.parser')
    p_tag = soup.find('p')
    formatted = pagescraper.format_soup(p_tag)
    assert formatted == {"p": ["Test"]}

def test_format_soup_empty():
    """Test formatting on an empty tag."""
    html = '<div></div>'
    soup = BeautifulSoup(html, 'html.parser')
    div_tag = soup.find('div')
    formatted = pagescraper.format_soup(div_tag)
    # Acceptable outputs: {'div': []}, {'div': ['']}, or {'div': None}
    assert formatted['div'] in (None, [], [""])

@patch('pagescraper.fetch_page')
def test_scrape_page(mock_fetch_page):
    """Test the scrape_page function and JSON output."""
    html = '''
    <html>
      <body>
        <a href="/test">Test Link</a>
        <img src="test.jpg" alt="Test Image">
        <p>Hello World</p>
      </body>
    </html>
    '''
    dummy_soup = BeautifulSoup(html, 'html.parser')
    mock_fetch_page.return_value = dummy_soup
    test_url = "http://example.com/test"

    pagescraper.scrape_page(test_url)

    with open("output.json", "r", encoding="utf-8") as f:
        data = json.load(f)
    assert data['url'] == test_url
    assert 'links' in data
    assert 'images' in data
    assert 'text' in data
    assert 'html' in data
    os.remove("output.json")

if __name__ == "__main__":
    pytest.main()