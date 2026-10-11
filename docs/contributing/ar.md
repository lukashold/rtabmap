# المساهمة في Kantura

[English — الدليل الكامل](../../CONTRIBUTING.md) · [الشيفرة](https://github.com/lukashold/rtabmap/tree/kantura/main)

نرحب بالمساهمة في الشيفرة والترجمة والتصميم والاختبارات على هاتف LiDAR حقيقي. فرع التطوير هو `kantura/main`. أنشئ فرعًا لتعديلك واجعل طلب السحب موجّهًا إلى `lukashold/rtabmap:kantura/main`.

تحتاج إلى المستودع الكامل وNode.js 24 وpnpm 11.25.0.

```sh
git clone --branch kantura/main https://github.com/lukashold/rtabmap.git
cd rtabmap/tools/scan-workspace
pnpm install --frozen-lockfile
pnpm test
pnpm build
pnpm start
```

افتح `http://localhost:4173`. توجد نصوص اللغات الجديدة كاملة في `locales/<language>.json`. حافظ على المفاتيح ومعرّفات المشاهد والأيقونات والوحدات والعناصر النائبة. بعد التعديل شغّل `pnpm locales:sync` ثم الاختبارات والبناء.

اذكر خطوات المشكلة والنتيجة المتوقعة والجهاز وإصدار iOS والالتزام الذي اختبرته. لا تنشر العينات الخاصة. قارن القياسات بأبعاد حقيقية مأخوذة بشريط قياس. RoomPlan للغرف الداخلية؛ استخدم نموذج LiDAR في الخارج. تحتفظ الغرف بإحداثيات مستقلة. فحص النقل يتحقق من أغلفة مستطيلة مبسّطة، وليس من الاصطدامات في درج كامل.

يتطلب بناء تطبيق iPhone وتوقيعه Mac وXcode. حافظ على إشعارات BSD والأطراف الثالثة؛ راجع [فحص الإصدار](../APP-STORE-RELEASE.md) لقيود تبعيات التطبيق. اذكر بوضوح في طلب السحب ما اختبرته وما لم تختبره بعد.
