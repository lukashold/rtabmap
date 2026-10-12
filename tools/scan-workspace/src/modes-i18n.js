const keys = ['panoramaJob', 'generatedJob', 'imageInputHelp', 'foregroundReady', 'generatedWarning', 'panoramaPhotosHelp', 'generatedSource'];
const rows = {
  de: [
    'Fotos → 360°-Panorama', 'Einzelbild → KI-3D-Entwurf',
    'Ein JPEG- oder PNG-Bild, höchstens 20 MiB.',
    'Das Motiv ist bereits freigestellt oder hat einen einfarbigen, neutralen Hintergrund.',
    'Die Geometrie einschließlich unsichtbarer Seiten wird geschätzt. Nur zum Ansehen, keine Vermessungsgrundlage. Diese optionale KI benötigt separat heruntergeladene Modelle; der Download kann groß sein.',
    'Überlappende Fotos aufnehmen und dabei um denselben Kameramittelpunkt drehen. Keine größeren Schritte machen. Fehlende Bereiche, auch an den Polen, bleiben sichtbar unbekannt. Keine Tiefe und keine Messungen.',
    'KI-generiert aus einem Bild; keine erfasste 3D-Geometrie.',
  ],
  en: [
    'Photos → 360° panorama', 'Single image → AI 3D concept',
    'One JPEG or PNG image, up to 20 MiB.',
    'The subject is already isolated or has a plain, neutral background.',
    'Geometry, including unseen sides, is estimated. For viewing only, not a basis for measurements. This optional AI requires separately downloaded models; downloads can be large.',
    'Take overlapping photos while rotating around the same camera centre. Avoid taking large steps. Missing areas, including the poles, remain visibly unknown. No depth or measurements.',
    'AI-generated from one image; not captured 3D geometry.',
  ],
  fr: [
    'Photos → panorama à 360°', 'Image unique → concept 3D par IA',
    'Une image JPEG ou PNG, de 20 Mio maximum.',
    'Le sujet est déjà détouré ou possède un arrière-plan uni et neutre.',
    'La géométrie, y compris les faces invisibles, est estimée. Pour la visualisation uniquement, sans valeur de référence pour les mesures. Cette IA facultative nécessite des modèles téléchargés séparément ; leur téléchargement peut être volumineux.',
    'Prenez des photos qui se chevauchent en tournant autour du même centre optique. Évitez les grands déplacements. Les zones manquantes, notamment aux pôles, restent visiblement inconnues. Aucune profondeur ni mesure.',
    'Généré par IA à partir d’une image ; ce n’est pas une géométrie 3D capturée.',
  ],
  es: [
    'Fotos → panorama de 360°', 'Una imagen → concepto 3D con IA',
    'Una imagen JPEG o PNG, de hasta 20 MiB.',
    'El sujeto ya está aislado o tiene un fondo liso y neutro.',
    'La geometría, incluidas las caras no visibles, se estima. Solo para visualizar, no como base de mediciones. Esta IA opcional requiere modelos descargados por separado; la descarga puede ser grande.',
    'Toma fotos superpuestas mientras giras alrededor del mismo centro de la cámara. Evita dar pasos grandes. Las zonas que faltan, incluidos los polos, siguen mostrándose como desconocidas. Sin profundidad ni mediciones.',
    'Generado con IA a partir de una imagen; no es geometría 3D capturada.',
  ],
  it: [
    'Foto → panorama a 360°', 'Immagine singola → concept 3D con IA',
    'Un’immagine JPEG o PNG, fino a 20 MiB.',
    'Il soggetto è già scontornato oppure ha uno sfondo uniforme e neutro.',
    'La geometria, comprese le parti non visibili, viene stimata. Solo per la visualizzazione, non come base per misurazioni. Questa IA facoltativa richiede modelli scaricati separatamente; il download può essere grande.',
    'Scatta foto sovrapposte ruotando attorno allo stesso centro della fotocamera. Evita spostamenti ampi. Le aree mancanti, compresi i poli, restano visibilmente sconosciute. Nessuna profondità né misurazione.',
    'Generato con IA da un’immagine; non è geometria 3D acquisita.',
  ],
  'zh-Hans': [
    '照片 → 360°全景', '单张图片 → AI三维构想',
    '一张JPEG或PNG图片，最大20 MiB。',
    '主体已抠出，或背景为中性的纯色。',
    '几何形状（包括不可见的侧面）由模型估算。仅供查看，不可作为测量依据。此可选AI功能需要另行下载模型，下载量可能较大。',
    '拍摄相互重叠的照片，并围绕同一个相机中心旋转。避免大幅移动。缺失区域（包括全景的顶部和底部）会明确保留为未知。没有深度信息，不支持测量。',
    '由单张图片通过AI生成，并非实测采集的三维几何。',
  ],
  pt: [
    'Fotografias → panorama de 360°', 'Imagem única → conceito 3D com IA',
    'Uma imagem JPEG ou PNG, até 20 MiB.',
    'O motivo já está recortado ou tem um fundo liso e neutro.',
    'A geometria, incluindo as faces não visíveis, é estimada. Apenas para visualização, não serve de base para medições. Esta IA opcional necessita de modelos descarregados separadamente; a transferência pode ser grande.',
    'Tire fotografias sobrepostas enquanto roda em torno do mesmo centro da câmara. Evite deslocações grandes. As áreas em falta, incluindo os polos, continuam visivelmente desconhecidas. Sem profundidade nem medições.',
    'Gerado por IA a partir de uma imagem; não é geometria 3D captada.',
  ],
  ar: [
    'صور ← بانوراما 360°', 'صورة واحدة ← تصوّر ثلاثي الأبعاد بالذكاء الاصطناعي',
    'صورة واحدة بصيغة JPEG أو PNG، بحد أقصى 20 MiB.',
    'العنصر معزول بالفعل عن الخلفية، أو خلفيته موحّدة ومحايدة اللون.',
    'تُقدَّر الهندسة، بما فيها الجوانب غير المرئية. للعرض فقط، وليست أساسًا للقياسات. تتطلب ميزة الذكاء الاصطناعي الاختيارية هذه تنزيل نماذج منفصلة، وقد يكون حجم التنزيل كبيرًا.',
    'التقط صورًا متداخلة مع الدوران حول مركز الكاميرا نفسه. تجنّب الخطوات الكبيرة. تظل المناطق المفقودة، بما فيها القطبان، ظاهرة بوصفها مجهولة. لا توجد معلومات عمق أو قياسات.',
    'مولَّد بالذكاء الاصطناعي من صورة واحدة؛ وليس هندسة ثلاثية الأبعاد جرى التقاطها.',
  ],
  hi: [
    'फ़ोटो → 360° पैनोरमा', 'एक चित्र → AI से 3D कल्पना',
    'एक JPEG या PNG चित्र, अधिकतम 20 MiB।',
    'विषय को पहले ही पृष्ठभूमि से अलग किया गया है या उसकी पृष्ठभूमि सादी और तटस्थ रंग की है।',
    'न दिखाई देने वाले हिस्सों सहित पूरी ज्यामिति का अनुमान लगाया जाता है। केवल देखने के लिए, माप लेने का आधार नहीं। इस वैकल्पिक AI सुविधा के लिए मॉडल अलग से डाउनलोड करने होंगे; डाउनलोड बड़ा हो सकता है।',
    'कैमरे के एक ही केंद्र के चारों ओर घूमते हुए आपस में ओवरलैप करने वाली फ़ोटो लें। बड़े कदम लेकर स्थान न बदलें। ऊपर और नीचे के ध्रुवों सहित छूटे हुए हिस्से स्पष्ट रूप से अज्ञात रहेंगे। न गहराई की जानकारी, न मापन।',
    'एक चित्र से AI द्वारा बनाया गया; यह कैप्चर की गई 3D ज्यामिति नहीं है।',
  ],
  bn: [
    'ছবি → ৩৬০° প্যানোরামা', 'একটি ছবি → AI দিয়ে 3D ধারণা',
    'একটি JPEG বা PNG ছবি, সর্বোচ্চ 20 MiB।',
    'বিষয়টি ইতিমধ্যেই পটভূমি থেকে আলাদা করা হয়েছে অথবা পটভূমি একরঙা ও নিরপেক্ষ।',
    'অদৃশ্য দিকগুলোসহ জ্যামিতি অনুমান করা হয়। শুধু দেখার জন্য, পরিমাপের ভিত্তি নয়। এই ঐচ্ছিক AI সুবিধার জন্য মডেল আলাদাভাবে ডাউনলোড করতে হবে; ডাউনলোডের আকার বড় হতে পারে।',
    'ক্যামেরার একই কেন্দ্রের চারদিকে ঘুরে পরস্পর আংশিক মিলে যায় এমন ছবি তুলুন। বড় পদক্ষেপে স্থান বদলাবেন না। ওপর ও নিচের মেরুসহ অনুপস্থিত অংশগুলো স্পষ্টভাবে অজানা থাকবে। গভীরতার তথ্য বা পরিমাপ নেই।',
    'একটি ছবি থেকে AI দিয়ে তৈরি; এটি ধারণ করা 3D জ্যামিতি নয়।',
  ],
  ru: [
    'Фотографии → панорама 360°', 'Одно изображение → 3D-концепт с ИИ',
    'Одно изображение JPEG или PNG размером до 20 МиБ.',
    'Объект уже отделён от фона либо фон однотонный и нейтральный.',
    'Геометрия, включая невидимые стороны, оценивается моделью. Только для просмотра, не для измерений. Эта дополнительная функция ИИ требует отдельно загруженных моделей; объём загрузки может быть большим.',
    'Делайте перекрывающиеся снимки, вращая камеру вокруг одного и того же оптического центра. Избегайте больших перемещений. Пропущенные области, включая полюса, остаются явно неизвестными. Данных о глубине и измерений нет.',
    'Создано ИИ по одному изображению; это не геометрия, полученная 3D-съёмкой.',
  ],
  ja: [
    '写真 → 360°パノラマ', '画像1枚 → AIによる3Dイメージ',
    'JPEGまたはPNG画像1枚、最大20 MiB。',
    '被写体はすでに切り抜かれているか、背景が無地で落ち着いた色になっています。',
    '見えない側面を含め、形状は推定されます。閲覧専用で、寸法測定の根拠にはできません。この任意のAI機能にはモデルの別途ダウンロードが必要で、容量が大きい場合があります。',
    '同じカメラの中心を軸に回転し、重なりのある写真を撮影してください。大きく移動しないでください。上下の極を含む未撮影の部分は、未知の領域として明示されます。深度情報や測定機能はありません。',
    '画像1枚からAIで生成したもので、撮影によって取得した3D形状ではありません。',
  ],
  ko: [
    '사진 → 360° 파노라마', '이미지 한 장 → AI 3D 구상',
    'JPEG 또는 PNG 이미지 한 장, 최대 20 MiB.',
    '피사체가 이미 배경에서 분리되어 있거나 배경이 중립적인 단색입니다.',
    '보이지 않는 면을 포함한 형상은 추정됩니다. 보기 전용이며 측정의 근거로 사용할 수 없습니다. 이 선택적 AI 기능은 모델을 별도로 다운로드해야 하며, 다운로드 용량이 클 수 있습니다.',
    '카메라의 같은 중심을 축으로 회전하며 서로 겹치는 사진을 촬영하세요. 크게 이동하지 마세요. 위아래 극점을 포함한 누락 영역은 알 수 없는 부분으로 명확히 남습니다. 깊이 정보나 측정 기능은 없습니다.',
    '이미지 한 장에서 AI로 생성한 형상이며, 촬영으로 얻은 3D 형상이 아닙니다.',
  ],
  id: [
    'Foto → panorama 360°', 'Satu gambar → konsep 3D dengan AI',
    'Satu gambar JPEG atau PNG, maksimal 20 MiB.',
    'Subjek sudah dipisahkan dari latar atau memiliki latar polos dan netral.',
    'Geometri, termasuk sisi yang tidak terlihat, diperkirakan. Hanya untuk dilihat, bukan dasar pengukuran. Fitur AI opsional ini memerlukan model yang diunduh terpisah; ukuran unduhannya bisa besar.',
    'Ambil foto yang saling tumpang tindih sambil berputar pada pusat kamera yang sama. Hindari langkah besar. Bagian yang hilang, termasuk kutub, tetap ditampilkan sebagai area yang tidak diketahui. Tanpa kedalaman atau pengukuran.',
    'Dihasilkan AI dari satu gambar; bukan geometri 3D hasil perekaman.',
  ],
  tr: [
    'Fotoğraflar → 360° panorama', 'Tek görüntü → yapay zekâ ile 3B taslak',
    'En fazla 20 MiB boyutunda bir JPEG veya PNG görüntüsü.',
    'Nesne zaten arka plandan ayrılmış veya düz, nötr bir arka plana sahip.',
    'Görünmeyen yüzler dâhil geometri tahmin edilir. Yalnızca görüntüleme içindir, ölçüm dayanağı değildir. Bu isteğe bağlı yapay zekâ özelliği ayrıca indirilen modeller gerektirir; indirme boyutu büyük olabilir.',
    'Kameranın aynı merkezi etrafında dönerek örtüşen fotoğraflar çekin. Büyük adımlarla yer değiştirmeyin. Kutuplar dâhil eksik alanlar açıkça bilinmeyen olarak kalır. Derinlik veya ölçüm yoktur.',
    'Tek görüntüden yapay zekâ ile oluşturulmuştur; çekimle elde edilmiş 3B geometri değildir.',
  ],
};

const qualityKeys = ['qualityReview', 'camera_pose_ambiguity', 'repeated_camera_views', 'insufficient_parallax'];
const qualityRows = {
  de: ['Rekonstruktion prüfen', 'Die Kamerapositionen passen möglicherweise nicht zu den Bildern. Neu aufnehmen; dieses Modell nicht zum Ausmessen verwenden.', 'Viele wiederholte Blickpunkte. Die Aufnahme mit mehr verschiedenen Positionen ergänzen.', 'Zu wenig Bewegung zwischen den Blickpunkten. Für 3D um das Motiv bewegen; Drehen auf der Stelle gehört zum Panoramamodus.'],
  en: ['Review reconstruction', 'Camera positions may not match the images. Capture again; do not use this model for measurements.', 'Many repeated viewpoints. Add photos from more varied positions.', 'Too little movement between viewpoints. For 3D, move around the subject; rotating in place is for panorama mode.'],
  fr: ['Vérifier la reconstruction', 'Les positions de la caméra peuvent ne pas correspondre aux images. Refaites la capture ; n’utilisez pas ce modèle pour mesurer.', 'De nombreux points de vue se répètent. Ajoutez des photos prises depuis des positions plus variées.', 'Trop peu de déplacement entre les points de vue. Pour la 3D, déplacez-vous autour du sujet ; tourner sur place correspond au mode panorama.'],
  es: ['Revisar la reconstrucción', 'Puede que las posiciones de la cámara no coincidan con las imágenes. Repite la captura; no uses este modelo para medir.', 'Hay muchos puntos de vista repetidos. Añade fotos desde posiciones más variadas.', 'Hay muy poco desplazamiento entre los puntos de vista. Para 3D, muévete alrededor del sujeto; girar sin desplazarte corresponde al modo panorama.'],
  it: ['Controllare la ricostruzione', 'Le posizioni della fotocamera potrebbero non corrispondere alle immagini. Ripeti l’acquisizione; non usare questo modello per misurare.', 'Molti punti di vista si ripetono. Aggiungi foto da posizioni più varie.', 'Lo spostamento tra i punti di vista è insufficiente. Per il 3D, muoviti attorno al soggetto; ruotare sul posto è adatto alla modalità panorama.'],
  'zh-Hans': ['检查重建结果', '相机位置可能与图像不符。请重新拍摄，不要使用此模型测量。', '许多拍摄位置重复。请从更多不同位置补拍照片。', '拍摄位置之间的移动太少。拍摄三维模型时，请绕主体移动；原地旋转适用于全景模式。'],
  pt: ['Verificar a reconstrução', 'As posições da câmara podem não corresponder às imagens. Repita a captura; não utilize este modelo para medir.', 'Muitos pontos de vista repetem-se. Acrescente fotografias tiradas de posições mais variadas.', 'Há pouco deslocamento entre os pontos de vista. Para 3D, desloque-se à volta do motivo; rodar no mesmo sítio destina-se ao modo panorama.'],
  ar: ['مراجعة إعادة البناء', 'قد لا تتطابق مواضع الكاميرا مع الصور. أعد الالتقاط، ولا تستخدم هذا النموذج للقياس.', 'تتكرر مواضع التصوير كثيرًا. أضف صورًا من مواضع أكثر تنوعًا.', 'الحركة بين مواضع التصوير قليلة جدًا. لإنشاء نموذج ثلاثي الأبعاد، تحرّك حول العنصر؛ أما الدوران في المكان فهو لوضع البانوراما.'],
  hi: ['पुनर्निर्माण की जाँच करें', 'कैमरे की स्थितियाँ चित्रों से मेल नहीं खा सकती हैं। दोबारा कैप्चर करें; इस मॉडल का उपयोग माप लेने के लिए न करें।', 'कई तस्वीरें उन्हीं जगहों से ली गई हैं। अधिक अलग-अलग स्थानों से तस्वीरें जोड़ें।', 'तस्वीरें लेते समय स्थान बहुत कम बदला गया है। 3D के लिए विषय के चारों ओर चलें; एक जगह खड़े होकर घूमना पैनोरमा मोड के लिए है।'],
  bn: ['পুনর্গঠনের ফল যাচাই করুন', 'ক্যামেরার অবস্থান ছবির সঙ্গে না-ও মিলতে পারে। আবার ছবি তুলুন; এই মডেল দিয়ে মাপ নেবেন না।', 'অনেক ছবি একই অবস্থান থেকে তোলা হয়েছে। আরও ভিন্ন ভিন্ন অবস্থান থেকে ছবি যোগ করুন।', 'ছবি তোলার অবস্থানগুলোর মধ্যে চলাচল খুব কম। 3D-এর জন্য বিষয়টির চারপাশে চলুন; একই জায়গায় দাঁড়িয়ে ঘোরা প্যানোরামা মোডের জন্য।'],
  ru: ['Проверить реконструкцию', 'Положения камеры могут не соответствовать снимкам. Повторите съёмку; не используйте эту модель для измерений.', 'Много повторяющихся точек съёмки. Добавьте фотографии с более разнообразных позиций.', 'Между точками съёмки слишком мало перемещения. Для 3D двигайтесь вокруг объекта; вращение на месте подходит для режима панорамы.'],
  ja: ['再構成結果を確認', 'カメラの位置が画像と一致していない可能性があります。撮影し直してください。このモデルを寸法測定に使用しないでください。', '同じ位置からの撮影が多くなっています。さらに異なる位置から撮った写真を追加してください。', '撮影位置の間の移動が少なすぎます。3D用の撮影では被写体の周囲を移動してください。その場で回転する撮影はパノラマモード用です。'],
  ko: ['재구성 결과 확인', '카메라 위치가 이미지와 맞지 않을 수 있습니다. 다시 촬영하고, 이 모델을 측정에 사용하지 마세요.', '같은 위치에서 촬영한 사진이 많습니다. 더 다양한 위치에서 찍은 사진을 추가하세요.', '촬영 위치 사이의 이동이 너무 적습니다. 3D 촬영 시 피사체 주위를 이동하세요. 제자리 회전은 파노라마 모드에 적합합니다.'],
  id: ['Periksa hasil rekonstruksi', 'Posisi kamera mungkin tidak sesuai dengan gambar. Ambil ulang; jangan gunakan model ini untuk pengukuran.', 'Banyak posisi pengambilan gambar berulang. Tambahkan foto dari posisi yang lebih bervariasi.', 'Perpindahan antarposisi terlalu sedikit. Untuk 3D, bergeraklah mengelilingi subjek; berputar di tempat digunakan untuk mode panorama.'],
  tr: ['Yeniden oluşturmayı kontrol et', 'Kamera konumları görüntülerle eşleşmiyor olabilir. Yeniden çekim yapın; bu modeli ölçüm için kullanmayın.', 'Birçok çekim konumu tekrarlanıyor. Daha farklı konumlardan çekilmiş fotoğraflar ekleyin.', 'Çekim konumları arasında çok az hareket var. 3B için nesnenin etrafında hareket edin; yerinde dönmek panorama modu içindir.'],
};

export const modesStrings = Object.freeze(Object.fromEntries(Object.entries(rows).map(([language, values]) => {
  const extra = qualityRows[language];
  if (values.length !== keys.length || !extra || extra.length !== qualityKeys.length) throw new Error(`Invalid capture-mode translation: ${language}`);
  const allKeys = [...keys, ...qualityKeys], allValues = [...values, ...extra];
  return [language, Object.freeze(Object.fromEntries(allKeys.map((key, index) => [key, allValues[index]])))];
})));
export const modesText = language => modesStrings[language] || modesStrings.en;
