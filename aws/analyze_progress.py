import json
import urllib.parse
import boto3
from openai import OpenAI
import os

print('Loading function')

# Initialize the S3 client using Boto3
s3 = boto3.client('s3')

# Fetch OpenAI API key from environment variable
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
client = OpenAI(api_key=OPENAI_API_KEY)

def format_data(response_text):
    # Locate the JSON inside the AI response
    json_code_start = response_text.find("\n{")
    json_code_end = response_text.rfind('```')

    if json_code_start == -1 or json_code_end == -1:
        raise ValueError("JSON code block not found in the response content.")

    json_string = response_text[json_code_start:json_code_end].strip()

    try:
        extracted_data = json.loads(json_string)
    except json.JSONDecodeError as e:
        raise ValueError(f"Error decoding JSON: {e}")

    return extracted_data


def storeDataToS3(data, row_id, a_email):
    bucket_name = 'artists-analyzed-data'
    fileName = 'artists-analyzed-data.json'

    # Add row_id at the top of the data
    structured_data = {
        "rowId": row_id,
        "artistEmail": a_email,
        "data": data
    }
    # print(f'Data stored in S3 structure: {structured_data}')

    uploadByteStream = bytes(json.dumps(structured_data, indent=4).encode('UTF-8'))
    # Store the data in S3
    s3.put_object(Bucket=bucket_name, Key=fileName, Body=uploadByteStream)

    # print(f'Data stored in S3 with rowId: {row_id}')
    

def lambda_handler(event, context):
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')

    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        # Parse JSON string into a dictionary
        parsed_data = json.loads(content)

        # Extract rowId and data, artistEmail
        row_id = parsed_data.get("rowId")
        scraped_data = parsed_data.get("data")
        a_email = parsed_data.get("artistEmail")

        # debug
        # print(f"Row ID: {row_id}     Artist eamil: {a_email}")
        # print(f"Scraped Data: {scraped_data}")


        prompt = f''' 
            Extract the following information from the artist profile located at the artist data.
            Return the result strictly in JSON format, wrapped in triple backticks (```).
            Example format:

            {{ "Name": "Jane Doe", "Location": "New York, USA", "Contact": "janedoe@gmail.com", "Theme": ["Nature", "Technology"], "Medium": ["Video", "Textile", "Performance"] }}

            Extract based on the following artist info:

            1. **Name**: [Artist Name]
            - Reasoning: Provide the complete name. If an alias is present (e.g., "Kite aka Suzanne Kite"), include both parts.

            2. **Location**: [Artist Location]
            - Must be a real, specific location on Earth.

            3. **Contact**: [Artist Contact Info]
            - Include only valid email, phone, or social media handles.

            4. **Theme**: [Art Theme]  
            - Return as a structured array of conceptual phrases that reflect the thematic focus of the work.  
            - Themes should reflect philosophical, emotional, bodily, or intellectual explorations (e.g., Birth, origin morphologies, visualizing human movement, plasticity of memory).  
            - Avoid listing materials, techniques, generic categories, or mediums (e.g., "video", "sound", "fabric").
            - If no full description is available, infer themes from poetic or conceptual language used in the titles or labels.  
            - Example output: ["Birth", "Origin Morphologies", "Visualizing Human Movement", "Plasticity of Memory"]


            5. **Medium**: [Art Medium]
            - Return a structured list of physical materials or digital technologies used in the artist’s work.  
            - Only include clean medium terms, not artwork titles or hybrid phrases.  
            - Normalize phrases like “VR Art” → “Virtual Reality”, and “Video & Sculpture” → ["Video", "Sculpture"].  
            - Avoid combining mediums with artwork titles (e.g., use "Sculpture", not "Mycelium Sculpture").  
            - Example output: ["Mycelium", "Kombucha Leather", "Virtual Reality", "Sculpture", "Real-time Generated Video", "Augmented Reality"]

            Artist data: 
            {scraped_data}
        '''

        print("Calling OpenAI...")

        openai_response = client.chat.completions.create(
            model="gpt-4-1106-preview",  # ← GPT-4.0 mini
            messages=[{
                "role": "user",
                "content": prompt
            }],
            temperature=0.2
        )

        message_content = openai_response.choices[0].message.content
        extracted_data = format_data(message_content)
        storeDataToS3(extracted_data, row_id, a_email)

        # print("OpenAI response:", openai_response)
        # print("message_content data:", message_content)
        # print("extracted_data data:", extracted_data)

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Analysis complete", "data": extracted_data})
        }

    except Exception as e:
        print(e)
        print(f'Error getting object {key} from bucket {bucket}. Error: {e}')
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
