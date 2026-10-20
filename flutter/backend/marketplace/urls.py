from django.urls import path
from .views import (
    ChargerListCreateView, BookingListCreateView, BookingRespondView,
    BookingStartView, BookingCompleteView, CreatePaymentOrderView,
    VerifyPaymentView, RazorpayWebhookView, DeviceTokenView, HostPayoutListView, HostPayoutRetryView, NotificationListView,
    NotificationReadView, ReviewListCreateView,
)
urlpatterns = [
    path("chargers/", ChargerListCreateView.as_view(), name="chargers"),
    path("bookings/", BookingListCreateView.as_view(), name="bookings"),
    path("bookings/<int:pk>/respond/", BookingRespondView.as_view(), name="booking-respond"),
    path("bookings/<int:pk>/start/", BookingStartView.as_view(), name="booking-start"),
    path("bookings/<int:pk>/complete/", BookingCompleteView.as_view(), name="booking-complete"),
    path("bookings/<int:pk>/payment-order/", CreatePaymentOrderView.as_view(), name="payment-order"),
    path("bookings/<int:pk>/verify-payment/", VerifyPaymentView.as_view(), name="verify-payment"),
    path("payments/razorpay/webhook/", RazorpayWebhookView.as_view(), name="razorpay-webhook"),
    path("devices/register/", DeviceTokenView.as_view(), name="device-register"),
    path("payouts/", HostPayoutListView.as_view(), name="host-payouts"),
    path("payouts/<int:pk>/retry/", HostPayoutRetryView.as_view(), name="host-payout-retry"),
    path("notifications/", NotificationListView.as_view(), name="notifications"),
    path("notifications/<int:pk>/read/", NotificationReadView.as_view(), name="notification-read"),
    path("reviews/", ReviewListCreateView.as_view(), name="reviews"),
]
