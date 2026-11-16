# Denizde Yürü — Korsan Prototipi

Godot 4.7 ve GDScript ile geliştirilen, bir korsan gemisinin güvertesinde geçen tek oyunculu birinci şahıs prototipi. Dalgalanan gemide yürüyebilir, dümene geçip rüzgârla yol alabilir, tayfayı ve gemi çevresinde uçan papağanı izleyebilirsiniz. Görsel dil; çizgi romanı andıran konturlar, cel shading ve 3B ortam içindeki 2B karakter çizimlerinden oluşur.

Bu depo oynanabilir bir mekanik denemesidir; tamamlanmış bir oyun değildir.

## Gereksinimler ve çalıştırma

- **Godot 4.7**; mevcut proje Godot **4.7.2** ile kontrol edilmiştir.
- Grafik arayüzüyle oynamak için Godot'un **Forward+** işleyicisini destekleyen bir grafik ortamı.
- Klavye ve fare.

Depoyu indirin veya klonlayın:

```sh
git clone https://github.com/c0detnr/pirate.git
cd pirate
```

Godot Project Manager üzerinden `project.godot` dosyasını içe aktarın; ilk varlık aktarımı tamamlandıktan sonra **F5** ile başlatın.

Terminalden, depo kökünde:

```sh
godot --headless --path . --import
godot --path .
```

İlk komut varlıkları hazırlar, ikinci komut oyunu açar. Sisteminizde çalıştırılabilir dosyanın adı `godot4` ise komutlarda `godot` yerine onu kullanın. Blender kurulumu gerekmez: oyun `assets/models/ship.glb` dosyasını kullanır; `.blend` dosyasının otomatik içe aktarımı kapalıdır. Oynamak için Python veya ek paket kurmanız gerekmez.

## Kontroller

| Girdi | Güvertede / suda | Dümendeyken |
| --- | --- | --- |
| **W / A / S / D** | Yürü / yüz | **A / D:** dümeni iskeleye / sancağa kır |
| **W / S** | İleri / geri hareket et | Her basışta yelkeni bir kademe aç / topla (0–3) |
| **Shift** | Güvertede koş | — |
| **Space** | Zıpla | — |
| **Fare** | Etrafa bak | Etrafa bak |
| **Sol tık** | Kılıç savur | — |
| **E** | Dümene geç; sudayken gemiye dön | Dümeni bırak |
| **Esc** | Fareyi serbest bırak | Fareyi serbest bırak |

Fare serbestken ilk sol tık yalnızca fareyi yeniden yakalar. Kılıç, yüzerken ve dümendeyken aşağı iner; bu durumlarda saldırı yapılamaz.

## İlk seyir

1. Oyun ana güvertede başlar. Her iki yandaki rampalarla baş ve kıç kasarasına çıkabilirsiniz.
2. Kıç kasarasındaki dümenin yakınına gelip ona bakın. **E — Dümene geç** istemi görünürken **E** tuşuna basın.
3. Yelkenler başlangıçta kapalıdır. **W** tuşuna ayrı ayrı basarak yelken seviyesini artırın.
4. **A / D** ile yön verin. Tuşu bıraktığınızda dümen yavaşça ortalanır. **S** ile yelken toplayabilir, **E** ile yeniden yürümeye başlayabilirsiniz.

Rüzgâr oku, rüzgârın **geldiği yönü** geminin pruvasına göre gösterir. Rüzgâr tam karşıdan yaklaşık ±40° içindeyse yelken itiş üretmez. Yandan ve kıç omuzluktan gelen rüzgâr en verimlidir; tam arkadan biraz daha yavaştır. Rüzgâr yönü zamanla yumuşakça değişir.

Gemi ağır hızlanır ve yavaşlar; hız sınırı **7 m/s**, yaklaşık **13,6 knot** değerindedir. Dümen, gemi dururken çok az etkilidir. HUD dümendeyken hızı, yelken seviyesini ve dümen konumunu gösterir. Yakındaki ada için basit bir kıyı engeli vardır; gemi kıyı sınırına girerse durdurulur.

## Mevcut özellikler

- Dalgalara göre yükselen, eğilen ve rüzgârla hafifçe yatan gemi; gemi hareket ederken oyuncuyu güvertede taşıyan hareket sistemi.
- Üç güverte seviyesi, yürünebilir rampalar, küpeşte çarpışmaları, yüzme ve **E** ile ortak güverte noktasına dönüş.
- Üç kademeli yelken, toplanma/açılma animasyonu, görünür dümen dönüşü ve görünen rüzgâra tepki veren yelkenler.
- Ana güvertede dolaşan **Lostromo**, **Topçu** ve **Miço**. Oyuncu yaklaşınca durup ona dönerler; 3 metre içinden bakıldığında adları görünür.
- Direklere, serenlere ve korkuluklara konan papağan. Gemiyle birlikte uçar, dümendeki oyuncuyla ilgilenir ve tünerken 1,5 metre yaklaşılınca ürker. 5 metre içinden bakıldığında adı görünür.
- Yürüyüş ve fare hareketine tepki veren birinci şahıs kılıç görünümü. Savurma sırasında 2 metrelik ışın sorgusu, uygun hedefin `take_hit(damage, from)` metodunu bir kez çağırır; hasar değeri 25'tir.
- Dünya koordinatlarında hesaplanan dalgalar, stilize su ve gökyüzü, gemi konturları ve su sıçraması efektleri.

## Prototipin sınırları

Görev, ekonomi, envanter, kayıt sistemi, çok oyunculu oyun ve tam bir savaş döngüsü bulunmaz. Tayfa ile papağan hasar hedefi değildir; kılıcın vuruş arayüzü otomatik testte oluşturulan hedef üzerinde doğrulanır. Gemi kinematik olarak ilerler; fizik tabanlı bir denizcilik simülatörü değildir. Ada teması basit bir mesafe sınırıyla çözülür. Yayınlanmış platform paketleri ve farklı cihazlarda performans garantisi bu deponun kapsamında değildir.

## Otomatik kontroller

Aşağıdaki komutları depo kökünden çalıştırın. Önce içe aktarımın tamamlanması gerekir:

```sh
godot --headless --path . --import
godot --headless --path . --quit-after 180
godot --headless --path . --fixed-fps 60 --script tests/ship_physics_smoke.gd
godot --headless --path . --fixed-fps 60 --script tests/crew_weapon_smoke.gd
godot --headless --path . --fixed-fps 60 --script tests/parrot_smoke.gd
```

| Kontrol | Kapsam |
| --- | --- |
| Ana sahne | Sahnenin başsız ortamda açılması ve 180 kare çalışması |
| `ship_physics_smoke.gd` | Gerçek gemi çarpışması ve oyuncu; rampalar, küpeşteler, yüzme/dönüş, yolcu kayması, rüzgâr, hız, dümen, yelkenler, kıyı ve uzak deniz takibi |
| `crew_weapon_smoke.gd` | Tayfa yön çizimleri ve güverte sınırları, oyuncuya dönme, isim istemi, kılıç durumları, tek vuruş ve saldırı engelleri |
| `parrot_smoke.gd` | Kanat döngüsü ve yön seçimi, 60 saniyelik seyirde uçuş sınırları, konma/kalkma, ürkme ve isim istemi |

Smoke testleri `failures=0` ve çıkış kodu `0` ile tamamlanmalıdır. Başsız sürücü işletim sistemi faresini yakalayamaz; kılıç testinde fare yakalama tıkının saldırı başlatmadığı kontrol edilir, saldırı döngüsü doğrudan metot çağrısıyla sınanır.

Bu kontroller görsel kabulün yerini tutmaz. Fareyle gerçek oynanış, görüntü kalitesi, rüzgâr oku, yelken/dümen animasyonları ve performans grafik arayüzünde ayrıca değerlendirilmelidir. `tests/visual_capture.gd` yerel ekran görüntüsü yardımcı betiğidir; çıktı dizini betikte sabit olduğundan taşınabilir bir otomatik test değildir.

Başsız ortamda kullanıcı dizinlerine yazma izni yoksa komutların başına şu öneki ekleyebilirsiniz:

```sh
env XDG_CONFIG_HOME=/tmp/pirate-godot/config XDG_DATA_HOME=/tmp/pirate-godot/data XDG_CACHE_HOME=/tmp/pirate-godot/cache godot --headless --path . --import
```

## Dizinler ve geliştirme notları

| Dizin | İçerik |
| --- | --- |
| `scenes/` | Ana ortam, gemi, oyuncu, tayfa ve papağan sahneleri |
| `scripts/` | Oyuncu, seyir, dalga/rüzgâr, tayfa, papağan, kılıç ve görünüm davranışları |
| `shaders/` | Su, yelken, gökyüzü, kontur ve karakter shader'ları |
| `assets/models/` | Kullanılan `ship.glb` ve Blender kaynak dosyası |
| `assets/art/` | Ham çizimler ve işlenmiş şeffaf PNG varlıkları |
| `tests/` | Başsız smoke testleri ve yerel görüntü yakalama yardımcısı |
| `tools/` | Çizim işleme aracı |
| `docs/` | [Çizim stil rehberi](docs/art_style.md) |

Dalga parametrelerinin ortak kaynağı `scripts/ocean.gd` dosyasıdır; hem geminin dalga örneklemesi hem su shader'ı buradaki veriyi kullanır. `Ocean` ve `Wind` autoload olarak yüklenir. Su yüzeyi kamerayı 2,5 metrelik ızgarada izler, dalga fazı dünya koordinatlarında korunur. Gemi çarpışması GLB içindeki gizlenen `ShipCollider` mesh'inden üretilir; yelken ve dümen pivotları çalışma anında kurulur.

Çizimleri yeniden işlemek isteyen geliştiriciler, `uv` kuruluysa aşağıdaki isteğe bağlı komutu kullanabilir. Bu araç `assets/art/` altındaki işlenmiş PNG dosyalarını yeniden yazar:

```sh
uv run --with pillow --with numpy --with scipy python tools/process_art.py
```

## Lisans

Bu depoda kod ve görseller için açık bir lisans beyanı bulunmuyor. Deponun herkese açık olması, kodun veya varlıkların yeniden dağıtım ve kullanım koşullarını tek başına belirlemez. Gemi modeli ve çizimler dahil varlıkların lisansı burada varsayılmamıştır.
