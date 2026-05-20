# gh-create-repos

gh, jq が必要です。

## 事前準備

- `gh auth login` でログイン済みであること
- 実行者が対象オーガニゼーションで「リポジトリの作成」と「コラボレーター/チーム権限の付与」を行える権限を持つこと
- `repos.json` に書く team は **slug**（URL に現れる識別子）であること

## 実行

```
chmod +x create_repos.sh
./create_repos.sh             # repos.json を自動で読む
./create_repos.sh /path/to/repos.json  # パス指定も可
```

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
- 実行終了時に「成功 / スキップ / 失敗」のサマリーを表示します。失敗が 1 件でもあれば終了コード 1 で終わります
