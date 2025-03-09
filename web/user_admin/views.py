from django.shortcuts import render, redirect
from django.contrib import messages
from django.views.generic import ListView, FormView
from .forms import UserForm
from .api_client import ApiClient
from .models import User

class UserListView(ListView):
    """View to display a list of users"""
    template_name = 'user_admin/user_list.html'
    context_object_name = 'users'
    
    def get_queryset(self):
        """Get users from the API"""
        api_client = ApiClient()
        return api_client.get_users()

class UserCreateView(FormView):
    """View to create a new user"""
    template_name = 'user_admin/user_form.html'
    form_class = UserForm
    success_url = '/'
    
    def form_valid(self, form):
        """Process valid form data"""
        try:
            user = form.to_user()
            api_client = ApiClient()
            created_user = api_client.create_user(user)
            messages.success(self.request, f"User {created_user.email} created successfully!")
            return super().form_valid(form)
        except Exception as e:
            messages.error(self.request, str(e))
            return self.form_invalid(form)