from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User, Charger, Booking, Payment, HostPayout, DeviceToken, AppNotification, Review

@admin.register(User)
class PlugsyUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (("Plugsy", {"fields": ("wants_to_host","razorpay_account_id")}),)
    list_display = ("username","email","wants_to_host","is_staff")

@admin.register(Charger)
class ChargerAdmin(admin.ModelAdmin):
    list_display = ("title","host","connector_type","price_per_kwh","is_available","is_published")
    list_filter = ("connector_type","is_available","is_published")
    search_fields = ("title","host__username","approximate_address")

@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ("id","charger","driver","status","payment_status","actual_kwh","total_amount","requested_at")
    list_filter = ("status","payment_status")

@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ("booking","order_id","payment_id","amount_paise","status","created_at")
    list_filter = ("status","provider")
    readonly_fields = ("order_id","payment_id","amount_paise","signature","created_at","paid_at")

@admin.register(HostPayout)
class HostPayoutAdmin(admin.ModelAdmin):
    list_display = ("host","payment","amount_paise","status","transfer_id","updated_at")
    list_filter = ("status",)
    search_fields = ("host__username","linked_account_id","transfer_id")
    readonly_fields = ("payment","host","linked_account_id","transfer_id","amount_paise","created_at","updated_at","error_message")

@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ("user","platform","updated_at")
    search_fields = ("user__username",)

@admin.register(AppNotification)
class AppNotificationAdmin(admin.ModelAdmin):
    list_display = ("user","title","kind","is_read","created_at")
    list_filter = ("kind","is_read")

@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display = ("charger","author","rating","created_at")
    list_filter = ("rating",)
