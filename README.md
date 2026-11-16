# Denizde Yürü

Godot 4.7 / GDScript ile ilk korsan prototipi. `project.godot` dosyasını Godot ile açıp **F5** ile çalıştırın. Terminal: `godot --path .`.

- **WASD:** yürü / suda yavaş yüz; **Shift:** koş; **Space:** zıpla.
- **Fare:** bak; **Esc:** fareyi bırak; **sol tık:** yeniden yakala.
- **E:** güverteye geri dön (geçici kurtarma etkileşimi).
- Her iki yandaki rampalardan kıç kasarasına (2,9 m) ve baş kasarasına (2,4 m) çıkabilirsiniz. Küpeşteler yürürken denize düşmeyi engeller.

`scenes/`: ana ortam, gemi ve oyuncu. `scripts/`: FPS, platform taşıma, gemi ve Ocean autoload. `shaders/`: toon su. `assets/models/ship.glb`: Blender gemisi (~22 × 6 m); `ship.blend` kaynak dosyasıdır.

Dalga parametrelerinin tek kaynağı `scripts/ocean.gd`; shader uniformları buradan doldurulur. Gemi fizik gövdesiyle simüle edilmez, dalgadan örnek alarak sallanır. Oyuncu geminin her fizik karesindeki tam konum/dönüş farkıyla taşınır; bakış ufku düz tutulur. Gemi ve oyuncu ayrı sahnelerdir; görsel parçalara `get_model_part("HelmWheel")` gibi Blender adlarıyla erişilebilir (`Sail_*`, `Gun*_Barrel`, `HatchGrate`). Yalnızca gizlenen `ShipCollider` mesh’inden gemi gövdesine trimesh çarpışması üretilir. Rampa çıkışlarında üst üste binen iç duvar yüzleri çalışma anında ayıklanır; görsel model değişmez. `.blend` içe aktarımı kapalıdır, Blender kurulumu gerekmez. Başlangıç ve E ile dönüş, ambarın yanındaki ana güverte noktasını paylaşır. Ada yaklaşık 100 m uzaktadır.

Kontrol: `godot --headless --path . --import`, ardından `godot --headless --path . --quit-after 180`.

Fizik duman testi (gerçek oyuncu, dalgalanan gemi): `godot --headless --path . --fixed-fps 60 --script tests/ship_physics_smoke.gd`. Spawn, 10 saniye kayma, dört rampa, üç güvertede iki yan küpeşte, yüzme ve E dönüşünü kontrol eder.
