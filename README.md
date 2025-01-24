# WebScraper

A simple Python program for **recursive web scraping** that collects text and images from a webpage, identifies and categorizes links (internal vs. external), and saves both the data and relevant metadata. Perfect for downstream analysis, particularly with Large Language Models (LLMs).

## Key Features

- **Recursive Crawling**  
  Traverses a website by following internal links to capture every page.

- **Text Extraction**  
  Extracts text content (headers, paragraphs, etc.) for easy analysis.

- **Image Retrieval**  
  Downloads images and logs their titles, `alt` text, and parent elements for contextual understanding.

- **Link Categorization**  
  Separates links into **internal** (within the same domain) and **external** (outside the domain).

- **Data Organization**  
  Automatically stores information (text, images, metadata) in a structured format—ideal for further use with AI/ML tools.

## How It Works

1. **Start Point**: Provide a URL; the scraper fetches its HTML content.  
2. **Parse Links**: Collects and categorizes links from the page.  
3. **Crawl Recursively**: Continues visiting internal links until the entire site is covered.  
4. **Extract & Download**: Gathers text, downloads images, and stores relevant metadata (like titles and HTML context).  
5. **Store Data**: All data is saved in a specified output folder, typically in JSON, CSV, or similar formats.

## Usage

1. **Install Dependencies**: `pip install -r requirements.txt`  
2. **Run the Script**: `python webscraper.py --url "https://example.com" --output "./my_output"`  
