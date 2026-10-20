# Generated for Plugsy marketplace lifecycle.
import django.contrib.auth.models
import django.contrib.auth.validators
import django.core.validators
import django.db.models.deletion
import django.utils.timezone
from decimal import Decimal
from django.conf import settings
from django.db import migrations, models

class Migration(migrations.Migration):
    initial = True
    dependencies = [("auth", "0012_alter_user_first_name_max_length")]
    operations = [
        migrations.CreateModel(
            name="User",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("password", models.CharField(max_length=128, verbose_name="password")),
                ("last_login", models.DateTimeField(blank=True, null=True, verbose_name="last login")),
                ("is_superuser", models.BooleanField(default=False, help_text="Designates that this user has all permissions without explicitly assigning them.", verbose_name="superuser status")),
                ("username", models.CharField(error_messages={"unique":"A user with that username already exists."}, max_length=150, unique=True, validators=[django.contrib.auth.validators.UnicodeUsernameValidator()], verbose_name="username")),
                ("first_name", models.CharField(blank=True, max_length=150, verbose_name="first name")),
                ("last_name", models.CharField(blank=True, max_length=150, verbose_name="last name")),
                ("email", models.EmailField(max_length=254, unique=True)),
                ("is_staff", models.BooleanField(default=False, help_text="Designates whether the user can log into this admin site.", verbose_name="staff status")),
                ("is_active", models.BooleanField(default=True, help_text="Designates whether this user should be treated as active. Unselect this instead of deleting accounts.", verbose_name="active")),
                ("date_joined", models.DateTimeField(default=django.utils.timezone.now, verbose_name="date joined")),
                ("wants_to_host", models.BooleanField(default=False)),
                ("groups", models.ManyToManyField(blank=True, help_text="The groups this user belongs to. A user will get all permissions granted to each of their groups.", related_name="user_set", related_query_name="user", to="auth.group", verbose_name="groups")),
                ("user_permissions", models.ManyToManyField(blank=True, help_text="Specific permissions for this user.", related_name="user_set", related_query_name="user", to="auth.permission", verbose_name="user permissions")),
            ],
            options={"verbose_name":"user","verbose_name_plural":"users"},
            managers=[("objects", django.contrib.auth.models.UserManager())],
        ),
        migrations.CreateModel(
            name="Charger",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("title", models.CharField(max_length=120)),
                ("latitude", models.DecimalField(decimal_places=6,max_digits=9)),
                ("longitude", models.DecimalField(decimal_places=6,max_digits=9)),
                ("price_per_kwh", models.DecimalField(decimal_places=2,max_digits=8,validators=[django.core.validators.MinValueValidator(Decimal("0.01"))])),
                ("power_kw", models.DecimalField(decimal_places=2,max_digits=6,validators=[django.core.validators.MinValueValidator(Decimal("0.1"))])),
                ("connector_type", models.CharField(choices=[("Type 2","Type 2"),("CCS2","CCS2"),("CHAdeMO","CHAdeMO"),("Bharat AC-001","Bharat AC-001"),("Bharat DC-001","Bharat DC-001"),("3-pin socket (verification required)","3-pin socket (verification required)")],max_length=50)),
                ("approximate_address", models.CharField(blank=True,max_length=250)),
                ("is_available", models.BooleanField(default=True)),
                ("is_published", models.BooleanField(default=False)),
                ("safety_confirmed", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("host", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE,related_name="chargers",to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name="Booking",
            fields=[
                ("id", models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name="ID")),
                ("status", models.CharField(choices=[("pending","pending"),("accepted","accepted"),("declined","declined"),("cancelled","cancelled"),("completed","completed")],default="pending",max_length=20)),
                ("requested_at", models.DateTimeField(auto_now_add=True)),
                ("responded_at", models.DateTimeField(blank=True,null=True)),
                ("session_started_at", models.DateTimeField(blank=True,null=True)),
                ("completed_at", models.DateTimeField(blank=True,null=True)),
                ("estimated_kwh", models.DecimalField(decimal_places=2,max_digits=7,validators=[django.core.validators.MinValueValidator(Decimal("0.1"))])),
                ("actual_kwh", models.DecimalField(blank=True,decimal_places=2,max_digits=7,null=True,validators=[django.core.validators.MinValueValidator(Decimal("0.01"))])),
                ("total_amount", models.DecimalField(blank=True,decimal_places=2,max_digits=9,null=True)),
                ("platform_fee", models.DecimalField(blank=True,decimal_places=2,max_digits=9,null=True)),
                ("payment_status", models.CharField(default="unpaid",max_length=20)),
                ("charger", models.ForeignKey(on_delete=django.db.models.deletion.PROTECT,related_name="bookings",to="marketplace.charger")),
                ("driver", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE,related_name="driver_bookings",to=settings.AUTH_USER_MODEL)),
            ],
            options={"ordering":["-requested_at"]},
        ),
        migrations.CreateModel(
            name="Payment",
            fields=[
                ("id", models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name="ID")),
                ("provider", models.CharField(default="razorpay",max_length=30)),
                ("order_id", models.CharField(max_length=100,unique=True)),
                ("payment_id", models.CharField(blank=True,max_length=100)),
                ("amount_paise", models.PositiveIntegerField()),
                ("currency", models.CharField(default="INR",max_length=3)),
                ("status", models.CharField(choices=[("created","created"),("paid","paid"),("failed","failed"),("refunded","refunded")],default="created",max_length=20)),
                ("signature", models.CharField(blank=True,max_length=256)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("paid_at", models.DateTimeField(blank=True,null=True)),
                ("booking", models.OneToOneField(on_delete=django.db.models.deletion.PROTECT,related_name="payment",to="marketplace.booking")),
            ],
        ),
        migrations.CreateModel(
            name="DeviceToken",
            fields=[
                ("id", models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name="ID")),
                ("token", models.TextField(unique=True)),
                ("platform", models.CharField(default="unknown",max_length=20)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE,related_name="device_tokens",to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name="AppNotification",
            fields=[
                ("id", models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name="ID")),
                ("title", models.CharField(max_length=120)),
                ("body", models.CharField(max_length=500)),
                ("kind", models.CharField(default="general",max_length=40)),
                ("is_read", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("booking", models.ForeignKey(blank=True,null=True,on_delete=django.db.models.deletion.CASCADE,related_name="notifications",to="marketplace.booking")),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE,related_name="app_notifications",to=settings.AUTH_USER_MODEL)),
            ],
            options={"ordering":["-created_at"]},
        ),
        migrations.CreateModel(
            name="Review",
            fields=[
                ("id", models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name="ID")),
                ("rating", models.PositiveSmallIntegerField(validators=[django.core.validators.MinValueValidator(1),django.core.validators.MaxValueValidator(5)])),
                ("comment", models.CharField(blank=True,max_length=1000)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("author", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE,related_name="charger_reviews",to=settings.AUTH_USER_MODEL)),
                ("booking", models.OneToOneField(on_delete=django.db.models.deletion.CASCADE,related_name="review",to="marketplace.booking")),
                ("charger", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE,related_name="reviews",to="marketplace.charger")),
            ],
            options={"ordering":["-created_at"]},
        ),
    ]
