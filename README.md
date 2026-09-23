# カミサマ、いま起きてる？（仮）

スマホの中に湧いた小さな町。住民は画面の外にいる「カミサマ（あなた）」を知っていて、祈ったり、恨んだり、勝手に意味を見出したりしている。
現実の時刻で勝手に進む町に、ちょっかいを出すだけのゲーム（プロトタイプ）。

**ブラウザで遊ぶ**：https://lockcole6.github.io/kamisama-ima-okiteru/

- 町は現実の時刻で動く。閉じている間も進み、戻ると「おかえりなさい」で留守中の出来事が分かる
- ちょっかいは4つ：**つつく**（1人）／**夢を見せる**（寝ている1人）／**風**（1か所）／**雨**（町全体）
- 住民はちょっかいと直前の出来事を結びつけて「教え」を作り、聖典に書き継いでいく
- セーブはブラウザごと。音は最初のタップのあとから鳴る

## 開発

- エンジン：Godot 4.7（GDScript）
- 開く：Godot で `project.godot` を開いて F5
- 設計：[DESIGN.md](DESIGN.md)（プロトタイプの実装仕様）、[CONCEPT.md](CONCEPT.md)（練り直したコンセプト v2）

| 場所 | 中身 |
|---|---|
| `scripts/autoload/` | 時計・シミュレーション（`Sim.gd`）・教義（`Doctrine.gd`）・ログ・セーブ・音 |
| `scripts/` `scripts/ui/` | 町・住民・画面の表示 |
| `data/` | 住民・祈り・ログ文のデータ（JSON） |
| `tools/` | 仮素材を作る Python スクリプト（`gen_art.py` 絵、`gen_audio.py` 音） |

### 書き出し

- Web：エディタの「プロジェクト → エクスポート → Web」。`build/web/` に出力し、`gh-pages` ブランチに置くと GitHub Pages で公開される
- Android：同じく「Android」。Android SDK と JDK 17 以上が必要

## 素材とライセンス

- 絵と音はすべて `tools/` のスクリプトで生成した仮素材
- フォント：[DotGothic16](https://github.com/fontworks-fonts/DotGothic16)、[M PLUS Rounded 1c](https://github.com/coz-m/MPLUS_FONTS)（どちらも SIL Open Font License 1.1。`assets/fonts/` にライセンス文を同梱）
