-- ZEN-KOTEI 初期データベース構築用 SQL スクリプト (Supabase SQL Editor で実行)

-- 拡張機能 (UUIDの自動生成用)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. users テーブル
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY, -- auth.users.id と紐付ける想定
    display_name TEXT NOT NULL DEFAULT 'みずき（あなた）',
    avatar_url TEXT,
    total_posts INT DEFAULT 0,
    total_followers INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. posts テーブル
CREATE TABLE IF NOT EXISTS public.posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id) NOT NULL,
    content TEXT NOT NULL,
    image_url TEXT,
    likes_count INT DEFAULT 0,
    status TEXT DEFAULT 'generating',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. replies テーブル
CREATE TABLE IF NOT EXISTS public.replies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID REFERENCES public.posts(id) ON DELETE CASCADE,
    author_name TEXT NOT NULL,
    author_img TEXT NOT NULL,
    content TEXT NOT NULL,
    is_hater BOOLEAN DEFAULT false,
    is_defender BOOLEAN DEFAULT false,
    display_order INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
