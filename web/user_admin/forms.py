from django import forms
from .models import User

class UserForm(forms.Form):
    """Form for creating a new user"""
    email = forms.EmailField(
        label="Email",
        required=True,
        widget=forms.EmailInput(attrs={'class': 'form-control'})
    )
    password = forms.CharField(
        label="Password",
        required=True,
        widget=forms.PasswordInput(attrs={'class': 'form-control'})
    )
    name = forms.CharField(
        label="Name",
        required=True,
        widget=forms.TextInput(attrs={'class': 'form-control'})
    )
    
    def clean_email(self):
        """Validate email format"""
        email = self.cleaned_data.get('email')
        if not email:
            raise forms.ValidationError("Email is required")
        return email
    
    def clean_password(self):
        """Validate password"""
        password = self.cleaned_data.get('password')
        if not password:
            raise forms.ValidationError("Password is required")
        if len(password) < 8:
            raise forms.ValidationError("Password must be at least 8 characters long")
        return password
    
    def to_user(self):
        """Convert form data to User object"""
        if not self.is_valid():
            return None
        
        user = User(
            email=self.cleaned_data['email'],
            name=self.cleaned_data['name']
        )
        # Add password as a separate attribute (not part of the model)
        user.password = self.cleaned_data['password']
        
        return user