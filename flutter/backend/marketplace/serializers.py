from django.contrib.auth import get_user_model
from rest_framework import serializers
from .models import Charger, Booking, Review
User = get_user_model()

class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    class Meta:
        model = User
        fields = ["id", "email", "username", "password", "wants_to_host"]
    def create(self, validated_data):
        password = validated_data.pop("password")
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user

class ChargerSerializer(serializers.ModelSerializer):
    host_username = serializers.CharField(source="host.username", read_only=True)
    average_rating = serializers.SerializerMethodField()
    review_count = serializers.SerializerMethodField()
    distance_km = serializers.SerializerMethodField()
    class Meta:
        model = Charger
        fields = ["id","title","latitude","longitude","price_per_kwh","power_kw","connector_type","approximate_address","is_available","is_published","safety_confirmed","host_username","average_rating","review_count","distance_km","created_at"]
        read_only_fields = ["id","host_username","average_rating","review_count","distance_km","created_at"]
    def _may_see_exact_location(self, obj):
        request = self.context.get("request")
        if not request or not request.user.is_authenticated: return False
        if obj.host_id == request.user.id: return True
        return Booking.objects.filter(charger=obj, driver=request.user, status__in=["accepted","completed"]).exists()
    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self._may_see_exact_location(instance):
            data["latitude"] = round(float(instance.latitude), 3)
            data["longitude"] = round(float(instance.longitude), 3)
        return data
    def get_average_rating(self,obj):
        from django.db.models import Avg
        return round(obj.reviews.aggregate(v=Avg("rating"))["v"] or 0,1)
    def get_review_count(self,obj): return obj.reviews.count()
    def get_distance_km(self,obj): return self.context.get("distances",{}).get(obj.id)

class BookingSerializer(serializers.ModelSerializer):
    charger_title = serializers.CharField(source="charger.title",read_only=True)
    charger_host = serializers.CharField(source="charger.host.username",read_only=True)
    driver_username = serializers.CharField(source="driver.username",read_only=True)
    is_host = serializers.SerializerMethodField()\n    has_review = serializers.SerializerMethodField()
    class Meta:
        model = Booking
        fields = ["id","charger","charger_title","charger_host","driver","driver_username","is_host","has_review","status","requested_at","responded_at","session_started_at","completed_at","estimated_kwh","actual_kwh","total_amount","platform_fee","payment_status"]
        read_only_fields = ["id","driver","status","requested_at","responded_at","session_started_at","completed_at","actual_kwh","total_amount","platform_fee","payment_status","charger_title","charger_host","driver_username","is_host"]
    def get_is_host(self,obj): return bool(self.context.get("request") and self.context["request"].user.is_authenticated and obj.charger.host_id==self.context["request"].user.id)\n    def get_has_review(self,obj): return Review.objects.filter(booking=obj).exists()

class ReviewSerializer(serializers.ModelSerializer):
    author_username = serializers.CharField(source="author.username",read_only=True)
    class Meta:
        model = Review
        fields = ["id","charger","booking","rating","comment","author_username","created_at"]
        read_only_fields = ["id","author_username","created_at"]
    def validate(self,attrs):
        booking=attrs.get("booking")
        request=self.context["request"]
        if booking.driver_id != request.user.id:
            raise serializers.ValidationError("Only the driver who booked can leave a review.")
        if booking.status != "completed" or booking.payment_status != "paid":
            raise serializers.ValidationError("Complete the charging session and payment before reviewing.")
        if booking.charger_id != attrs["charger"].id:
            raise serializers.ValidationError("Review charger must match the booking.")
        if Review.objects.filter(booking=booking).exists():
            raise serializers.ValidationError("This booking has already been reviewed.")
        return attrs
