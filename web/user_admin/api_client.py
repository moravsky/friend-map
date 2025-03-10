import requests
import json
from django.conf import settings
from .models import User

class ApiClient:
    """Client for interacting with the PostgREST API"""
    
    def __init__(self):
        self.base_url = settings.API_BASE_URL
        self.headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
    
    def get_users(self):
        """Get all users from the API"""
        response = requests.get(f"{self.base_url}/users", headers=self.headers)
        if response.status_code == 200:
            users_data = response.json()
            return [User.from_json(user_data) for user_data in users_data]
        return []
    
    def get_user(self, user_id):
        """Get a specific user by ID"""
        response = requests.get(f"{self.base_url}/users?id=eq.{user_id}", headers=self.headers)
        if response.status_code == 200 and response.json():
            return User.from_json(response.json()[0])
        return None
    
    def create_user(self, user):
        """Create a new user using the register_user function"""
        data = {
            'email': user.email,
            'password': user.password if hasattr(user, 'password') else '',
            'name': user.name
        }
        
        response = requests.post(
            f"{self.base_url}/rpc/register_user",
            headers=self.headers,
            json=data
        )
        
        if response.status_code in (200, 201):
            created_user = User.from_json(response.json())
            
            # If location data is provided, save it to location_history
            if hasattr(user, 'latitude') and hasattr(user, 'longitude') and user.latitude and user.longitude:
                self.add_user_location(created_user.id, user.latitude, user.longitude)
                
            return created_user
        
        # Handle errors
        error_message = response.text
        try:
            error_data = response.json()
            if 'message' in error_data:
                error_message = error_data['message']
        except:
            pass
        
        raise Exception(f"Failed to create user: {error_message}")
        
    def add_user_location(self, user_id, latitude, longitude):
        """Add a location history record for a user"""
        data = {
            'user_id': user_id,
            'latitude': latitude,
            'longitude': longitude
        }
        
        try:
            response = requests.post(
                f"{self.base_url}/rpc/add_location",
                headers=self.headers,
                json=data
            )
            
            if response.status_code not in (200, 201):
                print(f"Warning: Failed to save location for user {user_id}: {response.text}")
        except Exception as e:
            print(f"Error saving location: {str(e)}")