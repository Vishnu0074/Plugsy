from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, Charger, Booking, Review
@admin.register(User)
class PlugsyUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (("Plugsy",{"fields":("wants_to_host",)}),)
    list_display=("username","email","wants_to_host","is_staff")
@admin.register(Charger)
class ChargerAdmin(admin.ModelAdmin):
    list_display=("title","host","connector_type","price_per_kwh","is_available","is_published")
    list_filter=("connector_type","is_available","is_published")
    search_fields=("title","host__username","approximate_address")
@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display=("id","charger","driver","status","payment_status","requested_at")
    list_filter=("status","payment_status")
@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display=("charger","author","rating","created_at")
