-- triggers BEFORE DELETE يجب أن تعيد OLD؛ إعادة NEW تعيد NULL فيُلغى الحذف دون رسالة خطأ واضحة.
-- استبدال فحص service_role بـ auth.role() وفق نموذج Supabase.
-- الجلسات بدون request.jwt.claims (محرر SQL في لوحة التحكم، مهاجرة) تُسمح لها بالمرور لأن اتصال postgres يتجاوز RLS أصلاً.
CREATE OR REPLACE FUNCTION check_admin_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claims_empty boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF (SELECT auth.role()) = 'service_role' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  claims_empty := coalesce(current_setting('request.jwt.claims', true), '') = '';

  IF claims_empty THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  IF (auth.jwt() -> 'app_metadata' ->> 'role') IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'ليس لديك صلاحية الإدارة.';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;
