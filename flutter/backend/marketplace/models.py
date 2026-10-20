from django.conf import settings
from django.contrib.auth.models import AbstractUser
from django.core.validators import MinValueValidator, MaxValueValidator
from django.db import models

class User(AbstractUser):
    email = models.EmailField(unique=True)
    wants_to_host = models.BooleanField(default=False)

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
    estimated_kwh = models.DecimalField(max_digits=7,decimal_places=2,null=True,blank=True)
    total_amount = models.DecimalField(max_digits=9,decimal_places=2,null=True,blank=True)
    platform_fee = models.DecimalField(max_digits=9,decimal_places=2,null=True,blank=True)
    payment_status = models.CharField(max_length=20,default="unpaid")
    class Meta: ordering = ["-requested_at"]

class Review(models.Model):
    charger = models.ForeignKey(Charger,on_delete=models.CASCADE,related_name="reviews")
    author = models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name="charger_reviews")
    booking = models.OneToOneField(Booking,on_delete=models.CASCADE,related_name="review")
    rating = models.PositiveSmallIntegerField(validators=[MinValueValidator(1),MaxValueValidator(5)])
    comment = models.CharField(max_length=1000,blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    class Meta: ordering = ["-created_at"]
