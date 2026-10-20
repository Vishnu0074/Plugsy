from django.urls import path
from .views import ChargerListCreateView, BookingListCreateView, BookingRespondView, BookingCompleteView, ReviewListCreateView
urlpatterns = [
    path("chargers/", ChargerListCreateView.as_view()),
    path("bookings/", BookingListCreateView.as_view()),
    path("bookings/<int:pk>/respond/", BookingRespondView.as_view()),
    path("bookings/<int:pk>/complete/", BookingCompleteView.as_view()),
    path("reviews/", ReviewListCreateView.as_view()),
]
