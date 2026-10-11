# Kantura-তে অবদান রাখুন

[English — সম্পূর্ণ নির্দেশনা](../../CONTRIBUTING.md) · [সোর্স কোড](https://github.com/lukashold/rtabmap/tree/kantura/main)

কোড, অনুবাদ, ডিজাইন এবং আসল LiDAR ফোনে পরীক্ষা করে সাহায্য করুন। উন্নয়নের শাখা `kantura/main`। নিজের শাখা তৈরি করে Pull Request-এর লক্ষ্য রাখুন `lukashold/rtabmap:kantura/main`।

সম্পূর্ণ রিপোজিটরি, Node.js 24 এবং pnpm 11.25.0 প্রয়োজন।

```sh
git clone --branch kantura/main https://github.com/lukashold/rtabmap.git
cd rtabmap/tools/scan-workspace
pnpm install --frozen-lockfile
pnpm test
pnpm build
pnpm start
```

`http://localhost:4173` খুলুন। নতুন ভাষার সম্পূর্ণ লেখা `locales/<ভাষা>.json`-এ আছে। কী, দৃশ্যের পরিচয়, আইকন, একক ও placeholders অপরিবর্তিত রাখুন। বদলানোর পরে `pnpm locales:sync` চালিয়ে পরীক্ষা ও বিল্ড করুন।

সমস্যার ধাপ, প্রত্যাশিত ফল, ডিভাইস, iOS সংস্করণ ও পরীক্ষিত commit লিখুন। ব্যক্তিগত নমুনা প্রকাশ করবেন না। ফিতা দিয়ে বাস্তব মাপ নিয়ে তুলনা লিখুন। RoomPlan ঘরের ভেতরের জন্য; বাইরে LiDAR মডেল ব্যবহার করুন। প্রতিটি ঘর নিজের স্থানাঙ্ক রাখে। পরিবহন পরীক্ষা সরল আয়তাকার সীমা যাচাই করে, পুরো সিঁড়ির সংঘর্ষ নয়।

iPhone বিল্ড ও signing-এর জন্য Mac ও Xcode লাগবে। BSD এবং তৃতীয় পক্ষের নোটিশ রাখুন; [রিলিজের পরীক্ষা](../APP-STORE-RELEASE.md)-তে মূল অ্যাপের নির্ভরতার সীমা আছে। Pull Request-এ যা পরীক্ষা করেছেন এবং যা এখনো পরীক্ষা করেননি তা পরিষ্কার করে লিখুন।
