"""
WebSocket Lambda handlers for real-time dashboard updates.
Manages connections, disconnections, and broadcasts scraping updates.
"""

import json
import boto3
import os
import time
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
apigateway_management = None  # Initialized in broadcast functions

# Environment variables
CONNECTIONS_TABLE_NAME = os.environ.get('CONNECTIONS_TABLE_NAME')
WEBSOCKET_API_ENDPOINT = os.environ.get('WEBSOCKET_API_ENDPOINT')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'prod')

def get_connections_table():
    """Get the DynamoDB connections table."""
    if not CONNECTIONS_TABLE_NAME:
        raise ValueError("CONNECTIONS_TABLE_NAME environment variable not set")
    return dynamodb.Table(CONNECTIONS_TABLE_NAME)

def connect_handler(event, context):
    """
    Handle WebSocket connection events.
    Store connection ID in DynamoDB for later message broadcasting.
    """
    try:
        connection_id = event['requestContext']['connectionId']
        
        # Store connection in DynamoDB with TTL (24 hours)
        table = get_connections_table()
        table.put_item(
            Item={
                'connectionId': connection_id,
                'timestamp': int(time.time()),
                'ttl': int(time.time()) + 86400,  # 24 hours TTL
                'environment': ENVIRONMENT
            }
        )
        
        logger.info(f"WebSocket connection established: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Connected successfully'})
        }
        
    except Exception as e:
        logger.error(f"Error in connect_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to connect'})
        }

def disconnect_handler(event, context):
    """
    Handle WebSocket disconnection events.
    Remove connection ID from DynamoDB.
    """
    try:
        connection_id = event['requestContext']['connectionId']
        
        # Remove connection from DynamoDB
        table = get_connections_table()
        table.delete_item(
            Key={'connectionId': connection_id}
        )
        
        logger.info(f"WebSocket connection terminated: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Disconnected successfully'})
        }
        
    except Exception as e:
        logger.error(f"Error in disconnect_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to disconnect'})
        }

def message_handler(event, context):
    """
    Handle incoming WebSocket messages from clients.
    Currently just echoes back status - could be extended for client commands.
    """
    try:
        connection_id = event['requestContext']['connectionId']
        body = json.loads(event.get('body', '{}'))
        
        logger.info(f"Received message from {connection_id}: {body}")
        
        # Initialize API Gateway Management API client
        api_endpoint = event['requestContext']['domainName'] + '/' + event['requestContext']['stage']
        apigateway_management = boto3.client(
            'apigatewaymanagementapi',
            endpoint_url=f"https://{api_endpoint}"
        )
        
        # Echo back a status message
        response_message = {
            'type': 'status',
            'message': 'Message received',
            'timestamp': int(time.time()),
            'connectionId': connection_id
        }
        
        apigateway_management.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(response_message)
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Message processed'})
        }
        
    except Exception as e:
        logger.error(f"Error in message_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to process message'})
        }

def broadcast_handler(event, context):
    """
    Broadcast messages to all connected WebSocket clients.
    This function is called by the scraping Lambda to send real-time updates.
    """
    try:
        # Parse the incoming message
        if 'Records' in event:
            # Called via SQS
            message_body = json.loads(event['Records'][0]['body'])
        else:
            # Called directly
            message_body = event
        
        website_domain = message_body.get('website_domain')
        update_type = message_body.get('type', 'sitemap_update')
        data = message_body.get('data', {})
        
        if not website_domain:
            logger.error("No website_domain in broadcast message")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'website_domain required'})
            }
        
        # Get all active connections
        table = get_connections_table()
        response = table.scan()
        connections = response['Items']
        
        if not connections:
            logger.info("No active WebSocket connections to broadcast to")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'No active connections'})
            }
        
        # Initialize API Gateway Management API client
        if not WEBSOCKET_API_ENDPOINT:
            logger.error("WEBSOCKET_API_ENDPOINT not configured")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'WebSocket endpoint not configured'})
            }
        
        # Extract the API endpoint from the WebSocket URL
        api_endpoint = WEBSOCKET_API_ENDPOINT.replace('wss://', 'https://')
        apigateway_management = boto3.client(
            'apigatewaymanagementapi',
            endpoint_url=api_endpoint
        )
        
        # Prepare broadcast message
        broadcast_message = {
            'type': update_type,
            'website_domain': website_domain,
            'data': data,
            'timestamp': int(time.time())
        }
        
        message_json = json.dumps(broadcast_message)
        successful_sends = 0
        failed_sends = 0
        stale_connections = []
        
        # Broadcast to all connections
        for connection in connections:
            connection_id = connection['connectionId']
            
            try:
                apigateway_management.post_to_connection(
                    ConnectionId=connection_id,
                    Data=message_json
                )
                successful_sends += 1
                logger.info(f"Message sent to connection: {connection_id}")
                
            except ClientError as e:
                error_code = e.response['Error']['Code']
                
                if error_code == 'GoneException':
                    # Connection is stale, mark for removal
                    stale_connections.append(connection_id)
                    logger.info(f"Stale connection removed: {connection_id}")
                else:
                    failed_sends += 1
                    logger.error(f"Failed to send to {connection_id}: {str(e)}")
            
            except Exception as e:
                failed_sends += 1
                logger.error(f"Unexpected error sending to {connection_id}: {str(e)}")
        
        # Clean up stale connections
        for connection_id in stale_connections:
            try:
                table.delete_item(Key={'connectionId': connection_id})
            except Exception as e:
                logger.error(f"Failed to remove stale connection {connection_id}: {str(e)}")
        
        logger.info(f"Broadcast complete - Success: {successful_sends}, Failed: {failed_sends}, Stale: {len(stale_connections)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Broadcast completed',
                'successful_sends': successful_sends,
                'failed_sends': failed_sends,
                'stale_connections_removed': len(stale_connections)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in broadcast_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Broadcast failed: {str(e)}'})
        }

def invoke_broadcast(website_domain, update_type='sitemap_update', data=None):
    """
    Helper function to invoke the broadcast handler from other Lambda functions.
    This can be called from the scraping Lambda to send real-time updates.
    """
    if data is None:
        data = {}
    
    message = {
        'website_domain': website_domain,
        'type': update_type,
        'data': data
    }
    
    # You would typically invoke this via Lambda invoke or SQS
    # For now, return the message that should be sent
    return message
