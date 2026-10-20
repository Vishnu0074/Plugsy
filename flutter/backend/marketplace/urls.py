from django.urls import path
from .views import ChargerListCreateView, BookingListCreateView, BookingRespondView, ReviewListCreateView
urlpatterns = [path("chargers/",ChargerListCreateView.as_view()),path("bookings/",BookingListCreateView.as_view()),path("bookings/<int:pk>/respond/",BookingRespondView.as_view()),path("reviews/",ReviewListCreateView.as_view())]
