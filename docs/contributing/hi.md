# Kantura में योगदान

[English — पूर्ण निर्देश](../../CONTRIBUTING.md) · [स्रोत कोड](https://github.com/lukashold/rtabmap/tree/kantura/main)

कोड, अनुवाद, डिज़ाइन और असली LiDAR फ़ोन पर परीक्षण में मदद करें। विकास शाखा `kantura/main` है। अपनी शाखा बनाएँ और Pull Request का लक्ष्य `lukashold/rtabmap:kantura/main` रखें।

पूरी रिपॉज़िटरी, Node.js 24 और pnpm 11.25.0 चाहिए।

```sh
git clone --branch kantura/main https://github.com/lukashold/rtabmap.git
cd rtabmap/tools/scan-workspace
pnpm install --frozen-lockfile
pnpm test
pnpm build
pnpm start
```

`http://localhost:4173` खोलें। नई भाषा की पूरी सामग्री `locales/<भाषा>.json` में है। कुंजियाँ, दृश्य पहचानकर्ता, आइकन, इकाइयाँ और placeholders बनाए रखें। बदलाव के बाद `pnpm locales:sync` चलाएँ। फिर परीक्षण और बिल्ड करें।

समस्या के चरण, अपेक्षित परिणाम, डिवाइस, iOS संस्करण और जाँचा गया commit लिखें। निजी नमूने साझा न करें। वास्तविक माप को फीते से तुलना करके लिखें। RoomPlan अंदर के कमरों के लिए है; बाहर LiDAR मॉडल उपयोग करें। कमरे अपने अलग निर्देशांक रखते हैं। परिवहन जाँच सरल आयताकार सीमाएँ जाँचती है, पूरी सीढ़ी पर टकराव नहीं।

iPhone बिल्ड और signing के लिए Mac और Xcode चाहिए। BSD तथा तृतीय-पक्ष सूचनाएँ बनाए रखें; [रिलीज़ जाँच](../APP-STORE-RELEASE.md) में मूल ऐप की निर्भरता सीमाएँ दी गई हैं। अपने परीक्षण और बाकी अनजाँचे हिस्से Pull Request में स्पष्ट लिखें।
