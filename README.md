# Abuse Defender Node Safe

نسخه‌ای سازگارتر از ایده‌ی Abuse Defender برای سرورهای Node که Docker / PasarGuard روی آن‌ها اجرا می‌شود.

## هدف

این پروژه لیست رسمی IPهای Abuse Defender را روی `OUTPUT` اعمال می‌کند، اما از روش persistence نسخه اصلی استفاده نمی‌کند تا با Docker، PasarGuard Node و Boot سرور تداخل کمتری داشته باشد.

### تفاوت‌های اصلی

- بدون نصب `iptables-persistent` یا `netfilter-persistent`
- بدون ذخیره و Restore کامل `iptables-save`
- مدیریت فقط Chain اختصاصی پروژه
- Whitelist خودکار برای IPهای محلی، Default Gateway، Routeهای local و Docker subnetها
- Test Mode دو دقیقه‌ای با Rollback خودکار
- اعمال مجدد Ruleهای اختصاصی با systemd پس از Boot
- آپدیت روزانه لیست رسمی upstream
- پشتیبانی از whitelist و custom block

## Upstream

این پروژه بر پایه ایده و لیست رسمی پروژه زیر ساخته شده است:

- https://github.com/Kiya6955/Abuse-Defender
- Author: Kiya6955

لیست Abuse مستقیماً از upstream دریافت می‌شود و Rangeهای آن حذف نمی‌شوند.

## نصب

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/amiradineh74/abuse-defender-node-safe/main/install.sh)
```

Installer ابتدا فقط Test Mode دو دقیقه‌ای را فعال می‌کند. قبل از تأیید، SSH، Docker و Online بودن Node را بررسی کنید.

در صورت سالم بودن:

```bash
abuse-defender-node confirm
```

وضعیت:

```bash
abuse-defender-node status
```

حذف Ruleهای پروژه:

```bash
abuse-defender-node stop
```

Uninstall:

```bash
abuse-defender-node uninstall
```

## مهم

این پروژه نباید هم‌زمان با نصب قدیمی Abuse Defender یا `iptables-persistent/netfilter-persistent` استفاده شود. Installer در صورت تشخیص آن‌ها متوقف می‌شود.

## License / Attribution

پروژه upstream دارای مجوز سفارشی است. فایل `UPSTREAM-LICENSE.txt` را ببینید. این مخزن وابستگی یا تأیید رسمی از طرف سازنده اصلی را ادعا نمی‌کند.
