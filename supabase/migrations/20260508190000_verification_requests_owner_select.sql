-- السماح للطبيب بقراءة طلب التوثيق الخاص به فقط.
-- بعد 20260508160000 بقي INSERT للمالك و SELECT للأدمن، فخرج استعلام الطبيب فارغاً
-- وتبدو شاشة «عيادتي» وكأن الطلب غير موجود (أو تُعرض نموذج الإرسال من جديد).

DROP POLICY IF EXISTS "owner_select_own_verif" ON public.verification_requests;

CREATE POLICY "owner_select_own_verif"
  ON public.verification_requests
  FOR SELECT
  TO authenticated
  USING (doctor_id = auth.uid());
