from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion

class Migration(migrations.Migration):
    dependencies = [
        ("marketplace", "0001_initial"),
    ]
    operations = [
        migrations.AddField(
            model_name="user",
            name="razorpay_account_id",
            field=models.CharField(blank=True,max_length=100),
        ),
        migrations.CreateModel(
            name="HostPayout",
            fields=[
                ("id",models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name="ID")),
                ("linked_account_id",models.CharField(blank=True,max_length=100)),
                ("transfer_id",models.CharField(blank=True,max_length=100)),
                ("amount_paise",models.PositiveIntegerField()),
                ("status",models.CharField(choices=[("needs_setup","needs_setup"),("initiated","initiated"),("settled","settled"),("failed","failed"),("needs_reconciliation","needs_reconciliation")],default="needs_setup",max_length=30)),
                ("error_message",models.CharField(blank=True,max_length=500)),
                ("created_at",models.DateTimeField(auto_now_add=True)),
                ("updated_at",models.DateTimeField(auto_now=True)),
                ("host",models.ForeignKey(on_delete=django.db.models.deletion.PROTECT,related_name="payouts",to=settings.AUTH_USER_MODEL)),
                ("payment",models.OneToOneField(on_delete=django.db.models.deletion.PROTECT,related_name="host_payout",to="marketplace.payment")),
            ],
        ),
    ]
