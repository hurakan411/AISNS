import os
from dotenv import load_dotenv
from supabase import create_client


def main():
    load_dotenv()
    sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])
    res = sb.table("users").select("*").limit(1).execute()
    print(res.data)


if __name__ == "__main__":
    main()
