from django.conf import settings
from django.contrib.auth.models import AbstractUser
from django.core.validators import MinValueValidator, MaxValueValidator
from django.db import models

class User(AbstractUser):
    email = models.EmailField(unique=True)
    wants_to_host = models.BooleanField(default=False)
    # Populated only after the host completes the payment provider's linked-account/KYC onboarding.
    razorpay_account_id = models.CharField(max_length=100, blank=True)

class Charger(models.Model):
    CONNECTORS = [(x,x) for x in ["Type 2","CCS2","CHAdeMO","Bharat AC-001","Bharat DC-001","3-pin socket (verification required)"]]
    host = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name="chargers")
    title = models.CharField(max_length=120)
    latitude = models.DecimalField(max_digits=9,decimal_places=6)
    longitude = models.DecimalField(max_digits=9,decimal_places=6)
    price_per_kwh = models.DecimalField(max_digits=8,decimal_places=2,validators=[MinValueValidator(0.01)])
    power_kw = models.DecimalField(max_digits=6,decimal_places=2,validators=[MinValueValidator(0.1)])
    connector_type = models.CharField(max_length=50,choices=CONNECTORS)
    approximate_address = models.CharField(max_length=250,blank=True)
    is_available = models.BooleanField(default=True)
    is_published = models.BooleanField(default=False)
    safety_confirmed = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    def __str__(self): return f"{self.title} (@{self.host.username})"

class Booking(models.Model):
    STATUS = [(x,x) for x in ["pending","accepted","declined","cancelled","completed"]]
    charger = models.ForeignKey(Charger,on_delete=models.PROTECT,related_name="bookings")
    driver = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name="driver_bookings")
    status = models.CharField(max_length=20,choices=STATUS,default="pending")
    requested_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True,blank=True)
    session_started_at = models.DateTimeField(null=True,blank=True)
    completed_at = models.DateTimeField(null=True,blank=True)
    estimated_kwh = models.DecimalField(max_digits=7,decimal_places=2,validators=[MinValueValidator(0.1)])
    actual_kwh = models.DecimalField(max_digits=7,decimal_places=2,null=True,blank=True,validators=[MinValueValidator(0.01)])
    total_amount = models.DecimalField(max_digits=9,decimal_places=2,null=True,blank=True)
    platform_fee = models.DecimalField(max_digits=9,decimal_places=2,null=True,blank=True)
    payment_status = models.CharField(max_length=20,default="unpaid")
    class Meta: ordering = ["-requested_at"]

class Payment(models.Model):
    STATUS = [(x,x) for x in ["created","paid","failed","refunded"]]
    booking = models.OneToOneField(Booking,on_delete=models.PROTECT,related_name="payment")
    provider = models.CharField(max_length=30,default="razorpay")
    order_id = models.CharField(max_length=100,unique=True)
    payment_id = models.CharField(max_length=100,blank=True)
    amount_paise = models.PositiveIntegerField()
    currency = models.CharField(max_length=3,default="INR")
    status = models.CharField(max_length=20,choices=STATUS,default="created")
    signature = models.CharField(max_length=256,blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    paid_at = models.DateTimeField(null=True,blank=True)

class HostPayout(models.Model):
    STATUS = [(x,x) for x in ["needs_setup","initiated","transferred","failed","needs_reconciliation"]]
    payment = models.OneToOneField(Payment,on_delete=models.PROTECT,related_name="host_payout")
    host = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,related_name="payouts")
    linked_account_id = models.CharField(max_length=100,blank=True)
    transfer_id = models.CharField(max_length=100,blank=True)
    amount_paise = models.PositiveIntegerField()
    status = models.CharField(max_length=30,choices=STATUS,default="needs_setup")
    error_message = models.CharField(max_length=500,blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class DeviceToken(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name="device_tokens")
    token = models.TextField(unique=True)
    platform = models.CharField(max_length=20,default="unknown")
    updated_at = models.DateTimeField(auto_now=True)

class AppNotification(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name="app_notifications")
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=500)
    kind = models.CharField(max_length=40,default="general")
    booking = models.ForeignKey(Booking,null=True,blank=True,on_delete=models.CASCADE,related_name="notifications")
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta: ordering = ["-created_at"]

class Review(models.Model):
    charger = models.ForeignKey(Charger,on_delete=models.CASCADE,related_name="reviews")
    author = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name="charger_reviews")
    booking = models.OneToOneField(Booking,on_delete=models.CASCADE,related_name="review")
    rating = models.PositiveSmallIntegerField(validators=[MinValueValidator(1),MaxValueValidator(5)])
    comment = models.CharField(max_length=1000,blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta: ordering = ["-created_at"]
