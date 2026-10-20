from decimal import Decimal
from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient
from .models import Charger, Booking, Payment, Review, AppNotification

User = get_user_model()

class BookingLifecycleTests(TestCase):
    def setUp(self):
        self.host = User.objects.create_user(username="host_one", email="host@example.com", password="strong-pass-123", wants_to_host=True)
        self.driver = User.objects.create_user(username="driver_one", email="driver@example.com", password="strong-pass-123")
        self.charger = Charger.objects.create(
            host=self.host, title="Home Type 2", latitude=Decimal("9.931200"),
            longitude=Decimal("76.267300"), price_per_kwh=Decimal("12.50"),
            power_kw=Decimal("7.40"), connector_type="Type 2",
            is_available=True, is_published=True, safety_confirmed=True,
        )
        self.client = APIClient()

    def test_request_accept_start_complete_payment_review_lifecycle(self):
        self.client.force_authenticate(self.driver)
        response = self.client.post("/api/bookings/", {"charger": self.charger.id, "estimated_kwh": "10.00"}, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        booking_id = response.data["id"]
        self.assertEqual(response.data["status"], "pending")
        self.assertTrue(AppNotification.objects.filter(user=self.host, booking_id=booking_id, kind="booking_request").exists())

        self.client.force_authenticate(self.host)
        response = self.client.post(f"/api/bookings/{booking_id}/respond/", {"accept": True}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "accepted")

        response = self.client.post(f"/api/bookings/{booking_id}/start/", {}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNotNone(response.data["session_started_at"])

        response = self.client.post(f"/api/bookings/{booking_id}/complete/", {"actual_kwh": "8.40"}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "completed")
        self.assertEqual(Decimal(response.data["total_amount"]), Decimal("105.00"))

        booking = Booking.objects.get(pk=booking_id)
        Payment.objects.create(booking=booking, order_id="test_order_001", amount_paise=10500, status="paid", payment_id="test_payment_001")
        booking.payment_status = "paid"
        booking.save(update_fields=["payment_status"])

        self.client.force_authenticate(self.driver)
        response = self.client.post("/api/reviews/", {
            "charger": self.charger.id, "booking": booking_id,
            "rating": 5, "comment": "Easy to use and welcoming host.",
        }, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Review.objects.get(booking_id=booking_id).rating, 5)

    def test_non_host_cannot_accept_booking(self):
        booking = Booking.objects.create(charger=self.charger, driver=self.driver, estimated_kwh=Decimal("5.00"))
        self.client.force_authenticate(self.driver)
        response = self.client.post(f"/api/bookings/{booking.id}/respond/", {"accept": True}, format="json")
        self.assertEqual(response.status_code, 403)

    def test_driver_cannot_review_before_payment(self):
        booking = Booking.objects.create(
            charger=self.charger, driver=self.driver, status="completed",
            estimated_kwh=Decimal("5.00"), actual_kwh=Decimal("4.00"),
            total_amount=Decimal("50.00"),
        )
        self.client.force_authenticate(self.driver)
        response = self.client.post("/api/reviews/", {
            "charger": self.charger.id, "booking": booking.id, "rating": 4, "comment": "Test",
        }, format="json")
        self.assertEqual(response.status_code, 400)
