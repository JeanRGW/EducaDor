REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

REVOKE ALL ("avatar_key") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("avatar_key") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("email") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("email") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("full_name") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("full_name") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("id") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("id") ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ("needs_password") ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ("needs_password") ON TABLE "public"."profiles" TO "authenticated";
