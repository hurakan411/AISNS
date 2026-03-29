-- UPME! | AI SNS データベーススキーマ (Supabase SQL Editor で実行)
-- posts / replies はローカル管理のため、DB は users テーブルのみ

-- 拡張機能 (UUIDの自動生成用)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- users テーブル
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY,
    display_name TEXT NOT NULL DEFAULT 'みずき（あなた）',
    avatar_url TEXT,
    total_posts INT DEFAULT 0,
    total_followers INT DEFAULT 0,
    has_completed_onboarding BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 既存テーブルへのカラム追加（既にテーブルが存在する場合）
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS has_completed_onboarding BOOLEAN DEFAULT false;

-- 不要になった posts / replies テーブルを削除（既に存在する場合）
DROP TABLE IF EXISTS public.replies;
DROP TABLE IF EXISTS public.posts;
