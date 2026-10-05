<div dir="rtl">

# Abuse Defender Node Safe

نسخه‌ای ایمن‌تر برای استفاده از لیست رسمی `Abuse Defender` روی سرورهای لینوکسی، نودها و محیط‌هایی که روی آن‌ها `Docker` یا سرویس‌های تونل اجرا می‌شوند.

این پروژه با هدف جلوگیری از تداخل فایروال با نود و سرویس‌های شبکه طراحی شده و برخلاف روش اصلی، کل وضعیت `iptables` را در بوت ذخیره و بازیابی نمی‌کند.

> نسخه پایدار فعلی: `v1.0.0`

## ویژگی‌های اصلی

- استفاده از لیست رسمی پروژه اصلی بدون حذف رنج‌ها
- زنجیره اختصاصی با نام `PGAD_ABUSE_GUARD`
- عدم نصب `iptables-persistent` و `netfilter-persistent`
- عدم استفاده از بازیابی کامل `iptables-save` در بوت
- عدم پاک‌کردن یا بازنویسی Ruleهای موجودِ `Docker`، تونل‌ها و سایر سرویس‌های شبکه
- شناسایی خودکار آدرس‌های محلی، Gateway، Routeهای متصل و Subnetهای Docker
- محافظت از Routeهای حیاتی هنگام بوت با `Boot Guard`
- تست ایمن دو دقیقه‌ای با Rollback خودکار
- مدیریت کامل از طریق منوی تعاملی
- امکان روشن یا خاموش کردن Auto Update
- Whitelist و Custom Block قابل مدیریت
- حذف معمولی یا حذف کامل از داخل منو

## نصب

دستور زیر را با کاربر `root` اجرا کنید:

</div>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/amiradineh74/abuse-defender-node-safe/main/install.sh)
```

<div dir="rtl">

پس از نصب، منوی مدیریت به‌صورت خودکار باز می‌شود.

برای بازکردن دوباره منو در هر زمان:

</div>

```bash
abuse-defender
```

<div dir="rtl">

## منوی مدیریت

منوی اصلی شامل موارد زیر است:

</div>

```text
1) Enable protection
2) Disable protection
3) Safe test (2-minute auto rollback)
4) Status
5) View firewall rules / counters
6) Auto Update settings
7) Whitelist management
8) Custom Block management
9) Boot Safe Routes
10) Re-apply rules now
11) Uninstall Abuse Defender Node Safe
0) Exit
```

<div dir="rtl">

### فعال‌سازی محافظت

گزینه `Enable protection`، Ruleهای پروژه را فعال می‌کند و سرویس را برای بوت‌های بعدی نیز روشن می‌کند.

فعال‌کردن Protection به‌صورت خودکار Auto Update را روشن نمی‌کند. Auto Update از منوی خودش قابل کنترل است.

### تست ایمن

گزینه `Safe test` Ruleها را فعال می‌کند، اما یک Rollback خودکار دو دقیقه‌ای می‌سازد.

اگر در این زمان SSH، Docker، تونل یا نود دچار مشکل شود و کاربر هیچ کاری نکند، Ruleهای پروژه به‌صورت خودکار برداشته می‌شوند.

### Auto Update

از بخش `Auto Update settings` می‌توان:

- آپدیت روزانه را روشن کرد
- آپدیت روزانه را خاموش کرد
- لیست رسمی را همان لحظه به‌روزرسانی کرد
- وضعیت Timer را مشاهده کرد

لیست IP مستقیماً از پروژه اصلی دریافت می‌شود.

### Whitelist

از بخش `Whitelist management` می‌توان IP یا CIDR دلخواه را اضافه یا حذف کرد.

Whitelistهای دستی قبل از Ruleهای مسدودسازی اعمال می‌شوند.

### Custom Block

از بخش `Custom Block management` می‌توان IP یا CIDR دلخواه را علاوه بر لیست رسمی مسدود کرد.

## Boot Guard

یکی از تفاوت‌های مهم این نسخه، `Boot Guard` است.

هنگام نصب، Routeهای داخلی مهمی که ممکن است داخل رنج‌های خصوصی یا خاص قرار داشته باشند ثبت می‌شوند.

در بوت بعدی، قبل از اعمال Abuse Defender، سرویس تا آماده‌شدن Routeهای ثبت‌شده صبر می‌کند.

اگر Routeهای ضروری در بازه انتظار آماده نشوند، Ruleهای Abuse Defender اعمال نمی‌شوند. هدف این رفتار این است که محافظت فایروال باعث قطع نود یا تونل نشود.

Routeهای ذخیره‌شده از داخل منو قابل مشاهده و ثبت مجدد هستند.

## نحوه اعمال Ruleها

پروژه فقط یک Hook به `OUTPUT` اضافه می‌کند:

</div>

```text
OUTPUT
  └── PGAD_ABUSE_GUARD
```

<div dir="rtl">

داخل این Chain، ترتیب کلی به این شکل است:

1. استثناهای ایمن و Routeهای محلی
2. Whitelistهای دستی
3. Custom Blockها
4. لیست رسمی Abuse Defender
5. بازگشت به Ruleهای بعدی سیستم

به همین دلیل Ruleهای دیگری که از قبل روی `OUTPUT` وجود دارند حذف نمی‌شوند و بعد از بازگشت از Chain پروژه همچنان قابل اجرا هستند.

## حذف پروژه

در منوی Uninstall دو انتخاب وجود دارد:

### Remove runtime only

این گزینه:

- Ruleهای فعال پروژه را حذف می‌کند
- سرویس‌ها و Timerهای systemd را حذف می‌کند
- فایل‌های تنظیمات، Cache و Commandها را نگه می‌دارد

### Full uninstall (remove everything)

این گزینه همه موارد متعلق به پروژه را حذف می‌کند:

- Ruleهای فایروال
- سرویس‌ها و Timerهای systemd
- فایل‌های اجرایی
- Config
- Cache لیست
- Boot Safe Routes
- Backupهای ساخته‌شده توسط Installer
- ورودی‌های ساخته‌شده در `/etc/hosts`

بعد از Full Uninstall نباید اثری از پروژه روی سیستم باقی بماند.

## فایل‌های اصلی پروژه

</div>

```text
install.sh
abuse-defender-menu
abuse-defender-node
abuse-defender-boot-guard
/etc/abuse-defender-node/
/var/lib/abuse-defender-node/
```

<div dir="rtl">

نکته: فایل `abuse-defender-menu` هنگام نصب با نام `abuse-defender` روی سرور قرار می‌گیرد.

## سازگاری و نکات مهم

- این پروژه نباید هم‌زمان با نسخه قدیمی Abuse Defender اجرا شود.
- اگر `iptables-persistent` یا `netfilter-persistent` واقعاً نصب باشند، Installer متوقف می‌شود.
- Installer قبل از نصب فایل‌های اجرایی، Syntax آن‌ها را بررسی می‌کند.
- یک Backup مرجع از وضعیت فایروال هنگام نصب ساخته می‌شود، اما این Backup برای Restore خودکار بوت استفاده نمی‌شود.
- Full Uninstall، Backupهای ساخته‌شده توسط همین Installer را نیز پاک می‌کند.

## تست عملی

نسخه `v1.0.0` در یک نود واقعی با ترکیب زیر تست شده است:

- یک سرویس Node مبتنی بر Linux
- `Docker`
- یک سرویس تونل با Interfaceهای TUN
- Routeهای خصوصی روی Interfaceهای TUN

سناریوی نصب، فعال‌سازی، Reboot، بازگشت Routeها، سالم ماندن Node و تونل، Auto Update و Full Uninstall بررسی شده است.

این پروژه برای معماری‌های رایج Linux که ترافیک خروجی آن‌ها از `OUTPUT` عبور می‌کند طراحی شده است. سازگاری با تمام نرم‌افزارها، Policy Routingهای سفارشی، Namespaceهای جدا یا تمام توپولوژی‌های شبکه تضمین نمی‌شود. قبل از استفاده روی سرورهای حساس، ابتدا از گزینه `Safe test` استفاده کنید.

## پروژه اصلی

این پروژه از لیست رسمی پروژه زیر استفاده می‌کند:

</div>

- [Kiya6955/Abuse-Defender](https://github.com/Kiya6955/Abuse-Defender)

<div dir="rtl">

سازنده پروژه اصلی: `Kiya6955`

فایل لیست رسمی:

</div>

```text
https://raw.githubusercontent.com/Kiya6955/Abuse-Defender/main/abuse-ips.ipv4
```

<div dir="rtl">

## مجوز پروژه اصلی

مجوز پروژه اصلی یک مجوز سفارشی است و در فایل `UPSTREAM-LICENSE.txt` داخل همین مخزن نگهداری شده است.

طبق متن مجوز upstream، استفاده، تغییر و انتشار کد با شرایط ذکرشده در همان مجوز انجام می‌شود و محدودیت مشخصی برای استفاده از نرم‌افزار در محتوای ویدیویی منتشرشده دارد.

قبل از بازنشر یا ساخت محتوای ویدیویی، متن کامل `UPSTREAM-LICENSE.txt` را مطالعه کنید.

## نسخه

نسخه پایدار فعلی: `v1.0.0`

</div>
