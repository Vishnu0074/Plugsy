from django.contrib import admin
from django.urls import path, include
from rest_framework_simplejwt.views import TokenRefreshView
from marketplace.views import RegisterView, LoginView
urlpatterns = [path("admin/",admin.site.urls),path("api/auth/register/",RegisterView.as_view()),path("api/auth/login/",LoginView.as_view()),path("api/auth/refresh/",TokenRefreshView.as_view()),path("api/",include("marketplace.urls"))]
