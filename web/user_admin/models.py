from django.db import models

# These models are for representation only, not for database operations
# We'll use the REST API for actual data operations

class User:
    """
    Represents a user in the system.
    This is not a Django model as we're using the REST API.
    """
    def __init__(self, id=None, email=None, name=None, created_at=None,
                 latitude=None, longitude=None):
        self.id = id
        self.email = email
        self.name = name
        self.created_at = created_at
        self.latitude = latitude
        self.longitude = longitude

    @classmethod
    def from_json(cls, json_data):
        """Create a User instance from JSON data"""
        return cls(
            id=json_data.get('id'),
            email=json_data.get('email'),
            name=json_data.get('name'),
            created_at=json_data.get('created_at')
        )

    def to_json(self):
        """Convert User instance to JSON for API requests"""
        return {
            'email': self.email,
            'name': self.name
        }