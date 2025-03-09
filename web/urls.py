"""URL Configuration for web project."""

from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('user_admin.urls')),  # Include our user_admin app URLs
]