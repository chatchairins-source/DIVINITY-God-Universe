# DIVINITY — God Universe 🌍

เว็บเกมจริงที่เปิดเล่นได้จาก `index.html` → `play.html` โดยไม่ต้องติดตั้งโปรแกรม หรือสมัครสมาชิกในต้นแบบนี้

## ภายในเว็บ
- `index.html` หน้าแรกของเว็บไซต์ พร้อมเมนูและปุ่มเริ่ม/เล่นต่อ
- `play.html` **เกมจำลองโลก** เวอร์ชันล่าสุด (มนุษย์รายบุคคล, พลังพระเจ้า, ทรัพยากร, อัปเกรดดาว, จักรวาลดาวเดียว, และเวลามหากัป)
- `guide.html` คู่มือ, `privacy.html` ข้อมูลการบันทึก
- `manifest.webmanifest`, `service-worker.js` รองรับติดตั้งแบบ PWA และแคชเพื่อใช้เมื่อออฟไลน์ หลังเข้าเว็บผ่าน HTTPS ครั้งแรก
- `.github/workflows/pages.yml` เผยแพร่อัตโนมัติเมื่อ push main

## เผยแพร่ GitHub Pages

1. เปิด https://github.com/new สร้าง **Public** repo ชื่อ `DIVINITY-God-Universe` (แยกจาก QueueGo)
2. แตกไฟล์ ZIP แล้วอัปโหลดไฟล์ **ทั้งหมด** ในโฟลเดอร์นี้ลง root ของ branch `main`
3. Settings → Pages → Build and deployment → Source → **GitHub Actions**
4. ตรวจ Actions ให้เวิร์กโฟลว์ "Publish DIVINITY to GitHub Pages" สำเร็จ
5. เปิด `https://chatchairins-source.github.io/DIVINITY-God-Universe/` **หลัง deploy สำเร็จเท่านั้น**

หากจำเป็นใช้งาน Git ผ่านเครื่อง:

```bash
git init
git branch -M main
git add .
git commit -m "Launch DIVINITY website"
git remote add origin https://github.com/chatchairins-source/DIVINITY-God-Universe.git
git push -u origin main
```

## การบันทึกและกฎ

- เซฟเกมใน `localStorage`, รองรับนำเข้า/ส่งออก JSON และเล่นต่อบนเบราว์เซอร์เดียวกัน
- หนึ่งผู้เล่นหนึ่งดาว ไม่มี AI rivals/คู่แข่งจำลอง
- ระบบหลายผู้เล่นและสงครามข้ามดาวยังไม่เปิด
- **ไม่มีการชำระเงินจริง**: แพ็กเกจราคาเป็นตัวอย่าง ไม่เรียกเก็บเงินและไม่เพิ่มคริสตัลที่ซื้อด้วยเงินจริง
- เวลา 1 ปีบนดาว = 48 วันจำลอง; ปฏิทินมหากัปเป็นมาตราส่วนสำหรับเล่นเกม ไม่ใช่การแปลงระยะเวลาของกัปตามพระไตรปิฎกจริง
- GitHub Pages รองรับ frontend เท่านั้น; หากต้องการ login, ผู้เล่นหลายคน, และชำระเงิน ต้องเพิ่ม backend + การยืนยันธุรกรรมแบบเซิร์ฟเวอร์