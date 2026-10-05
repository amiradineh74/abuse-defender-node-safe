# Abuse Defender Node Safe

نسخه‌ای سازگار با Docker / PasarGuard Node که از لیست رسمی Abuse Defender استفاده می‌کند، اما از persistence کامل iptables استفاده نمی‌کند.

## نصب

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/amiradineh74/abuse-defender-node-safe/main/install.sh)
```

بعد از نصب، منوی مدیریت باز می‌شود. هر زمان هم می‌توان با این دستور دوباره منو را باز کرد:

```bash
abuse-defender
```

## قابلیت‌های منو

- فعال یا غیرفعال کردن Protection
- Safe Test دو دقیقه‌ای با Rollback خودکار
- مشاهده Status
- مشاهده Ruleها و Counterها
- روشن/خاموش کردن Auto Update روزانه
- آپدیت دستی لیست رسمی
- افزودن/حذف Whitelist
- افزودن/حذف Custom Block
- مشاهده و Refresh کردن Boot Safe Routes
- Re-apply دستی Ruleها
- Uninstall

## طراحی ایمن برای Node

- بدون `iptables-persistent` و `netfilter-persistent`
- بدون Restore کامل `iptables-save`
- فقط Chain اختصاصی `PGAD_ABUSE_GUARD`
- عدم Flush یا تغییر Ruleهای Docker / BackPack
- Whitelist خودکار برای آدرس‌های محلی، Gateway، Routeهای link و Docker subnetها
- Boot Guard: قبل از اعمال Ruleها در Boot منتظر Routeهای حیاتی ثبت‌شده می‌ماند
- اگر Routeهای ضروری آماده نشوند، Firewall پروژه اعمال نمی‌شود
- لیست رسمی upstream بدون حذف Rangeها استفاده می‌شود

## Upstream

پروژه و لیست اصلی:

- https://github.com/Kiya6955/Abuse-Defender
- Author: Kiya6955

لیست IPها مستقیماً از upstream دریافت می‌شود.

## License / Attribution

مجوز upstream در فایل `UPSTREAM-LICENSE.txt` قرار دارد. این پروژه وابستگی یا تأیید رسمی از طرف سازنده اصلی را ادعا نمی‌کند.
