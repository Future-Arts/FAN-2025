from bs4 import BeautifulSoup

def extract_text(soup, tag, class_name=None):
    """Extract text from a specific HTML tag and class."""
    if class_name:
        elements = soup.find_all(tag, class_=class_name)
    else:
        elements = soup.find_all(tag)
    return [element.get_text(strip=True) for element in elements]

def extract_links(soup, tag='a', class_name=None):
    """Extract all links from a specific HTML tag and class."""
    if class_name:
        elements = soup.find_all(tag, class_=class_name)
    else:
        elements = soup.find_all(tag)
    return [element.get('href') for element in elements if element.get('href')]

def extract_images(soup, tag='img', class_name=None):
    """Extract all image sources from a specific HTML tag and class."""
    if class_name:
        elements = soup.find_all(tag, class_=class_name)
    else:
        elements = soup.find_all(tag)
    return [element.get('src') for element in elements if element.get('src')]

def categorize_data(soup):
    """Categorize data into text, links, and images."""
    data = {
        'text': extract_text(soup, 'p'),
        'links': extract_links(soup),
        'images': extract_images(soup)
    }
    return data

def parse_html(html_content):
    """Parse HTML content using BeautifulSoup."""
    return BeautifulSoup(html_content, 'html.parser')