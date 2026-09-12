# 言語パック：クラスベースのオブジェクト指向言語（Java / C# / Kotlin ほか）

コアの手順に対する補足。**対象がこれらの言語のときだけ読む。**

## 1. インターフェースによる置きかえ

構築困難なオブジェクト（ネットワーク接続、DB コネクション、外部サービスの
クライアント）を持つクラスの切りはなし。`dependency-breaking.md` のパターン A
の具体形。

**1. 現状** — `HttpConnection` を直接持っているので実際に通信してしまう。

**2. 使っている操作だけのインターフェースを定義し、差しかえ口を開ける**

```java
public class ApiProxy {
    private IHttpConnection connection;
    public IHttpConnection replace(IHttpConnection connection) {
        IHttpConnection old = this.connection;
        this.connection = connection;
        return old;                       // 差しかえ前を返すと復元できる
    }
}
```

**3. モックを差しこんでテストする**

```java
@Test
public void user_list_is_empty_when_server_returns_OK_without_body() {
    api.replace(new MockConnection() {
        public Response get(String endpoint, Cookie cookie) { return Response.OK; }
    });
    assertThat(api.listUsers(), is(new ArrayList<User>()));
}
```

**4. 本番実装は元のオブジェクトをラップする**

```
IHttpConnection ←── HttpConnectionProxy ──has──> HttpConnection（本物）
       ↑
       └────────── MockConnection（テスト用）
```

`HttpConnectionProxy` は呼びだしを転送するだけの薄い層。**ここにロジックを
入れない。** テストされない層になるので薄く保つ。

**インターフェースには、対象が実際に呼んでいるメソッドだけを入れる。** 元の
クラスの全メソッドを写すと、モックの実装が重くなってテストを書く気が失われる。

## 2. この言語で使える強み

- **IDE の自動リファクタリング。** 自動リネーム・自動抽出・自動移動が信頼できる。
  `patterns.md`「5. 名前が意図を表さない」はテスト保護なしで実行してよい。
  機械的な変換は手作業と信頼性が段違い
- **可視性の段階が細かい。** `private` / パッケージ内 / `protected` / `public`。
  公開範囲を絞る作業（`patterns.md`「7. モジュール分割」の 4 番）が言語機能で
  できる。**1 項目の終わりは「可視性を狭められた」ところまで**と決めておく
- **モックライブラリが成熟している。** ただし `dependency-breaking.md`
  「モックの粒度」の警告はそのまま当てはまる。使いやすさに引かれて何でも
  モックすると、テストが実装の内部構造に過敏になる

## 3. 肥大化はクラスとパッケージの二層で起きる

`patterns.md`「3. 肥大化クラス／モジュール」は、これらの言語では**クラス**の
話として読める。ただし**上の層でも同じことが起きる**ので、両方を見る。

- **クラスの肥大化** — フィールドとメソッドの利用関係で分割線を探す（本文どおり）
- **パッケージの肥大化** — `util` `common` `helpers` `manager` パッケージは、
  C の `misc.c` と同じ理由で育つ。何も約束していないので何を入れてもよくなる。
  **`*Util` `*Manager` `*Helper` という名前のクラス**も同じ。名前が役割を
  語っていないので、置き場に困った `static` メソッドの行き先になる

**この言語では移動が安いので、やりきれる。** IDE の Move Class / Move Members は
参照を自動で追随するうえ、コンパイラが漏れを教える。だから
`patterns.md`「元のファイルが無くなることを終点にする」を実際に達成しやすい。
**移動のあと、可視性を狭められるかを必ず確かめる**（パッケージ内に閉じたなら
`public` を外す）。それが分割の成果で、そこまで進めないと依存は減っていない。

## 4. この言語で起きやすい落とし穴

- **`static` メソッド・`static` 初期化子への依存。** インターフェース化できない。
  呼びだしを薄いインスタンスメソッドで包み、そのメソッドを差しかえる
- **コンストラクタが重い。** `new` した時点で通信や DB 接続が走ると、
  テストでインスタンスを作れない。生成をファクトリーに追いだす
- **継承で共通化されたテスト。** 親クラスのテストを継承して差分だけ書く形は、
  リファクタリングで階層を変えるとまとめて壊れる。継承より合成に寄せる
- **アノテーション・リフレクション経由の参照。** `patterns.md`「9. 不要な
  コード」の裏取りで、grep が効かない。DI コンテナの設定、シリアライザ、
  ORM のマッピングを確認する
