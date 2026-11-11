"""Offline subscription simulation using the local token benchmark results."""

import argparse
import collections
import json
import math
from pathlib import Path
import statistics


ROOT = Path(__file__).resolve().parent.parent
LABELS = {
    "text_rank1": "テキスト・ランク1",
    "image1024_rank1": "1024×768画像・ランク1",
    "image4032_rank1": "4032×3024画像・ランク1",
    "text_rank10_full_memory": "テキスト・ランク10・常連3人の履歴上限",
    "image4032_rank10_full_memory": "4032×3024画像・ランク10・常連3人の履歴上限",
    "reply_thread_full_memory": "AIへの返信スレッド・常連の履歴あり",
    "onboarding": "オンボーディングのデモ返信",
}


def simulate(price, paid_users, post_limit, thread_limit, free_users, free_posts, free_threads, new_users, assumptions):
    unit = assumptions["budget_unit_cost_jpy"]
    proceeds = price / (1 + assumptions["sales_tax_rate"]) * (1 - assumptions["apple_commission_rate"])
    paid_api = post_limit * unit["post"] + thread_limit * unit["thread"]
    free_api = free_users * (free_posts * unit["post"] + free_threads * unit["thread"])
    onboarding_api = new_users * unit["onboarding"]
    fixed = assumptions["annual_membership_jpy"] / 12
    margin = proceeds - paid_api
    return {
        "monthly_price_jpy": price, "paid_users": paid_users,
        "post_limit": post_limit, "thread_limit": thread_limit,
        "free_users": free_users, "free_posts": free_posts,
        "free_threads": free_threads, "new_users": new_users,
        "net_subscription_proceeds_per_user_jpy": proceeds,
        "paid_api_per_user_jpy": paid_api, "contribution_per_user_jpy": margin,
        "free_api_total_jpy": free_api, "onboarding_api_total_jpy": onboarding_api,
        "monthly_membership_jpy": fixed,
        "monthly_profit_jpy": paid_users * margin - free_api - onboarding_api - fixed,
        "breakeven_paid_users": math.floor((fixed + free_api + onboarding_api) / margin) + 1 if margin > 0 else None,
    }


def main(args):
    data = json.loads(args.input.read_text(encoding="utf-8"))
    groups = collections.defaultdict(list)
    for sample in data["samples"]:
        groups[sample["case"]].append(sample)
    stats = {}
    for case, samples in groups.items():
        stats[case] = {
            "label": LABELS[case], "samples": len(samples),
            "input_min": min(s["input_tokens"] for s in samples),
            "input_max": max(s["input_tokens"] for s in samples),
            "output_min": min(s["output_tokens"] for s in samples),
            "output_max": max(s["output_tokens"] for s in samples),
            "reply_min": min(s["reply_count"] for s in samples),
            "reply_max": max(s["reply_count"] for s in samples),
            "mean_uncached_usd": statistics.mean(s["uncached_cost_usd"] for s in samples),
            "max_uncached_usd": max(s["uncached_cost_usd"] for s in samples),
            "mean_uncached_jpy": statistics.mean(s["uncached_cost_usd"] for s in samples) * args.fx,
            "max_uncached_jpy": max(s["uncached_cost_usd"] for s in samples) * args.fx,
        }
    post_max_usd = max(s["max_uncached_usd"] for case, s in stats.items() if case not in {"reply_thread_full_memory", "onboarding"})
    unit_usd = {
        "post": post_max_usd,
        "thread": stats["reply_thread_full_memory"]["max_uncached_usd"],
        "onboarding": stats["onboarding"]["max_uncached_usd"],
    }
    assumptions = {
        "fx_jpy_per_usd": args.fx,
        "annual_membership_jpy": args.annual_membership_jpy,
        "apple_commission_rate": args.commission,
        "sales_tax_rate": 0.10,
        "cost_buffer_multiplier": 2,
        "observed_max_uncached_unit_usd": unit_usd,
        "budget_unit_cost_jpy": {key: math.ceil(cost * args.fx * 2) for key, cost in unit_usd.items()},
        "membership_note": "Annual fee is an editable estimate ($99 converted at the scenario FX), not the user's actual receipt.",
        "simulation_note": "All users consume the entire specified monthly allowance; no advertising income or other operating costs. Quotas are hypothetical, not implemented.",
    }
    prices = [480, 680, 980, 1480]
    scenarios = [
        simulate(price, count, posts, threads, free, 3, 0, 0, assumptions)
        for posts, threads in [(30, 10), (60, 20), (100, 50)]
        for free in [0, 100, 1000]
        for count in [10, 50, 100]
        for price in prices
    ]
    result = {
        "sample_count": len(data["samples"]),
        "test_total_estimated_cost_usd": sum(s["estimated_cost_usd"] for s in data["samples"]),
        "case_stats": stats, "assumptions": assumptions, "scenarios": scenarios,
    }
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    yen = lambda value: f"{value:,.0f}円"
    report = [
        "# UPME API原価のローカル実測とサブスク収益試算", "", "計測日: 2026-11-09 / モデル: gpt-5.4-mini / 日本語", "",
        "## 実測条件", "",
        "既存バックエンドの生成関数をローカルで直接呼び出した。7条件を各3回、計21回。Render・PostHogへの送信やDB書き込みは行っていない。画像は個人情報を含まない合成の赤い花のシーンで、アプリと同じJPEG quality 50。実際の写真に対する応答品質の評価ではない。常連3人の負荷試験は、各常連に長期記憶8件×160文字、直近履歴3件×180文字を持たせた。ユーザー投稿本文は短文であり、長文投稿の上限試験ではない。", "",
        "ランク1は3〜5件、ランク10は10〜16件を要求する乱数シードを選択した。実際の返信数はモデルの出力によって変動し、1回は17件だった。生成結果の本文・画像・APIキー・ユーザーIDは結果ファイルに保存していない。", "",
        "## トークン数と1回あたり原価", "",
        "入力トークンには画像が含まれる。原価欄はキャッシュ割引なしの標準API単価による見積もり。実トークン数はAPIのusageから取得した。出力トークンの変動により、画像間の原価差は画像入力分だけとは一致しない。", "",
        "| 条件 | 入力tokens | 出力tokens | 平均原価 | 観測最大原価 |",
        "|---|---:|---:|---:|---:|",
    ]
    for item in stats.values():
        report.append(f"| {item['label']} | {item['input_min']:,}〜{item['input_max']:,} | {item['output_min']:,}〜{item['output_max']:,} | {item['mean_uncached_jpy']:.2f}円 | {item['max_uncached_jpy']:.2f}円 |")
    report += [
        "", f"今回の21回のAPI代は、キャッシュ割引を反映すると推定${result['test_total_estimated_cost_usd']:.6f}（{result['test_total_estimated_cost_usd'] * args.fx:.2f}円）。", "",
        "## 試算の前提", "",
        f"- 為替: 1USD={args.fx}円（試算値。実際のカード請求レートとは異なる）",
        f"- Apple Developer Program年会費: {yen(args.annual_membership_jpy)}、月割り{yen(args.annual_membership_jpy / 12)}。99USDの換算を仮置きしており、実際の日本円の会員費は領収書の金額で置き換える。",
        f"- 月額は税込。税相当分を1.1で除き、Apple手数料{args.commission:.0%}を差し引く概算（Small Business Program参加を仮定）。",
        "- 日本向けApple IAPの手数料は、現行条件ではSmall Business Program等が10%+決済5%=15%、通常初年度は21%+決済5%=26%。契約・地域条件はApp Store Connectの実際の収益を優先する。",
        "- 固定費は年会費の月割りだけ。API代の請求時税額・カード換算手数料・返金・割引・広告収入・サーバー代・人件費・所得税等は含めない。",
        "- 1投稿=ユーザー投稿に対するAI返信の一括生成1回（AIコメント1件ではない）。1返信=ユーザーがAIへ返信して3〜5件のスレッドを生成するAPI呼び出し1回。",
        "- 料金・上限は試算であり、実際のユーザーの支払意向や有料転換率を測定したものではない。",
        "", "実測最大のキャッシュ割引なし原価を2倍し、1円単位で切り上げた予算単価を使う。これは観測範囲外の絶対的な上限を保証する値ではない。", "",
        f"- 投稿生成: {yen(assumptions['budget_unit_cost_jpy']['post'])}/回",
        f"- 返信スレッド生成: {yen(assumptions['budget_unit_cost_jpy']['thread'])}/回",
        f"- 新規ユーザーのオンボーディング: {yen(assumptions['budget_unit_cost_jpy']['onboarding'])}/生成回",
        "", "## 有料会員の上限とAPI予算", "",
        "| 月間投稿生成 | 月間返信生成 | 1人あたり月API予算 |", "|---:|---:|---:|",
    ]
    unit = assumptions["budget_unit_cost_jpy"]
    for posts, threads in [(30, 10), (60, 20), (100, 50)]:
        report.append(f"| {posts}回 | {threads}回 | {yen(posts * unit['post'] + threads * unit['thread'])} |")
    for free in [0, 1000]:
        report += ["", f"## 月60投稿＋20返信を全員が使い切る場合（無料利用者{free:,}人）", "",
                   "無料ユーザーは1人月3投稿、返信0回。新規オンボーディングは0人として比較。無料ユーザー数と新規登録者数は仮定値。", "",
                   "| 月額 | 1人あたり限界利益 | 黒字化人数 | 有料10人の月利益 | 有料50人 | 有料100人 |", "|---:|---:|---:|---:|---:|---:|"]
        for price in prices:
            rows = [simulate(price, n, 60, 20, free, 3, 0, 0, assumptions) for n in [10, 50, 100]]
            report.append(f"| {yen(price)} | {yen(rows[0]['contribution_per_user_jpy'])} | {rows[0]['breakeven_paid_users']}人 | " + " | ".join(yen(r["monthly_profit_jpy"]) for r in rows) + " |")
    report += ["", "## 計算式", "",
               "月利益 = 有料会員数 × {税込月額 ÷ 1.1 × (1 − Apple手数料率) − 有料会員1人のAPI予算} − 無料ユーザーのAPI代 − 新規オンボーディングのAPI代 − 年会費 ÷ 12", "",
               "有料会員1人の限界利益が0円以下なら、人数を増やしてもこの条件では黒字化しない。回数制限を付ける場合、AIへの返信・再生成・オンボーディング等の追加API呼び出しも計上する必要がある。将来の自発AI投稿はまだ未実装のためこの試算には含めていない。", "",
               "## 出典・再現", "",
               "- OpenAI料金: https://developers.openai.com/api/docs/models/gpt-5.4-mini",
               "- Apple年会費: https://developer.apple.com/jp/help/account/membership/program-enrollment/",
               "- 日本向けApple IAP手数料: https://developer.apple.com/support/payment-options-on-the-app-store-in-japan/", "",
               "実測の再実行（API課金あり）: `python3 backend/measure_ai_usage.py --repeats 3 --max-cost-usd 0.50`", "",
               "試算だけの再計算（ネットワーク・課金なし）: `python3 backend/simulate_subscription.py --fx 158.3 --annual-membership-jpy 15672 --commission 0.15`", ""]
    args.report.write_text("\n".join(report), encoding="utf-8")
    print(json.dumps({"measured_cases": stats, "budget_unit_costs": unit, "report": str(args.report)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "docs/analysis/token-cost-2026-11-09.json")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/analysis/subscription-simulation-2026-11-09.json")
    parser.add_argument("--report", type=Path, default=ROOT / "docs/analysis/subscription-simulation-2026-11-09.md")
    parser.add_argument("--fx", type=float, default=158.3)
    parser.add_argument("--annual-membership-jpy", type=float, default=15672)
    parser.add_argument("--commission", type=float, default=0.15)
    main(parser.parse_args())
