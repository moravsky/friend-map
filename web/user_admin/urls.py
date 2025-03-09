from django.urls import path
from . import views

app_name = 'user_admin'

urlpatterns = [
    path('', views.UserListView.as_view(), name='user_list'),
    path('users/create/', views.UserCreateView.as_view(), name='user_create'),
]