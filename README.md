# gh-create-repos

gh, jq が必要です。

## 事前準備

- `gh auth login` でログイン済みであること
- 実行者が対象オーガニゼーションで「リポジトリの作成」と「コラボレーター/チーム権限の付与」を行える権限を持つこと
- `repos.json` に書く team は **slug**（URL に現れる識別子）であること

## 実行

```
chmod +x create_repos.sh
./create_repos.sh                          # repos.json を自動で読む
./create_repos.sh /path/to/repos.json      # パス指定も可
./create_repos.sh --add-permissions        # 既存リポジトリにも権限を追加・更新する
./create_repos.sh --add-permissions /path/to/repos.json
```

### オプション

- `--add-permissions`
  既存リポジトリに対しても権限付与処理を実行します。リポジトリ作成はスキップし、`repos.json` に書かれた権限のみ追加・更新します。
  **JSON に書かれていない既存の権限（コラボレーター/チーム）は変更しません。**
- `-h`, `--help`
  使い方を表示します。

## 設定ファイル (repos.json)

```
{
  "org": "your-org-name",
  "repos": [
    {
      "name": "repo-name-01",
      "admin":      ["alice", "bob"],   ← 個人に Admin
      "admin_team": ["leads-team"],     ← チームに Admin
      "write":      ["charlie"],        ← 個人に Write
      "write_team": ["dev-team"]        ← チームに Write
    }
  ]
}
```
不要な権限は空配列 [] にしておけばスキップされます。

## 挙動

- 同名リポジトリが既に存在する場合は **何もせずスキップ** します（README の更新も権限の再付与も行いません）
- `--add-permissions` を付けた場合は、既存リポジトリに対しても `repos.json` の権限を追加・更新します。新規にコラボレーター/チームを追加する用途を想定しており、JSON に記載のない既存の権限は削除しません
- 実行終了時に「成功 / 権限更新 / スキップ / 失敗」のサマリーを表示します。失敗が 1 件でもあれば終了コード 1 で終わります
