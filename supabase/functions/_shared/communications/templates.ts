export interface DeliveryContext {
  readonly communication_id: string;
  readonly communication_type: string;
  readonly locale: string;
  readonly recipient: string;
  readonly appointment_id?: string | null;
  readonly pet_id?: string | null;
  readonly organization_invitation_id?: string | null;
  readonly guardianship_invitation_id?: string | null;
  readonly organization_name?: string | null;
  readonly pet_name?: string | null;
  readonly clinic_name?: string | null;
  readonly scheduled_start_at?: string | null;
  readonly timezone_name?: string | null;
  readonly reschedule_proposal_id?: string | null;
}

export interface RenderedEmail {
  readonly subject: string;
  readonly text: string;
  readonly html: string;
}

export interface RenderedPush {
  readonly title: string;
  readonly body: string;
  readonly data: Readonly<Record<string, string>>;
}

function htmlEscape(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

function localizedDate(context: DeliveryContext): string | null {
  if (!context.scheduled_start_at) return null;
  const date = new Date(context.scheduled_start_at);
  if (Number.isNaN(date.valueOf())) return null;
  try {
    return new Intl.DateTimeFormat(context.locale || "es-ES", {
      dateStyle: "full",
      timeStyle: "short",
      timeZone: context.timezone_name ?? "Europe/Madrid",
    }).format(date);
  } catch {
    return new Intl.DateTimeFormat("es-ES", {
      dateStyle: "full",
      timeStyle: "short",
      timeZone: "Europe/Madrid",
    }).format(date);
  }
}

const APPOINTMENT_LABELS: Readonly<Record<string, string>> = Object.freeze({
  APPOINTMENT_REQUESTED: "se ha solicitado",
  APPOINTMENT_CONFIRMED: "se ha confirmado",
  APPOINTMENT_CANCELLED: "se ha cancelado",
  APPOINTMENT_RESCHEDULE_PROPOSED: "tiene una propuesta de cambio de horario",
  APPOINTMENT_RESCHEDULE_ACCEPTED: "se ha reprogramado",
  APPOINTMENT_COMPLETED: "ha finalizado",
  APPOINTMENT_NO_SHOW: "se ha registrado como no realizada",
  APPOINTMENT_REMINDER: "se acerca",
  APPOINTMENT_ALTERNATIVE_TIME_PROPOSED:
    "tiene una propuesta de otro horario de la clínica",
});

// SPEC-COM-003 BR-71: a Clinic alternative time for a REQUESTED Appointment.
// The copy must say that the Clinic proposes another time for the request and
// that the Appointment is not yet confirmed — never that it changed or was
// confirmed.
const ALTERNATIVE_TIME_PROPOSED = "APPOINTMENT_ALTERNATIVE_TIME_PROPOSED";
const NOT_YET_CONFIRMED = "La cita aún no está confirmada.";

export function renderEmail(
  context: DeliveryContext,
  publicAppUrl: string,
  invitationSecret?: string,
): RenderedEmail {
  if (context.communication_type === "ORGANIZATION_INVITATION") {
    if (!context.organization_invitation_id || !invitationSecret) {
      throw new TypeError("Invitation context is incomplete");
    }
    const url = new URL("/invitations/organization/accept", publicAppUrl);
    url.searchParams.set("invitation", context.organization_invitation_id);
    url.hash = new URLSearchParams({ secret: invitationSecret }).toString();
    const organization = context.organization_name ??
      "una organización veterinaria";
    const text =
      `Te han invitado a unirte a ${organization}. Acepta la invitación: ${url.toString()}`;
    return {
      subject: `Invitación para unirte a ${organization}`,
      text,
      html: `<p>Te han invitado a unirte a <strong>${
        htmlEscape(organization)
      }</strong>.</p><p><a href="${
        htmlEscape(url.toString())
      }">Aceptar invitación</a></p>`,
    };
  }

  if (context.communication_type === "GUARDIANSHIP_INVITATION") {
    if (!context.guardianship_invitation_id || !invitationSecret) {
      throw new TypeError("Invitation context is incomplete");
    }
    const url = new URL("/invitations/guardianship/accept", publicAppUrl);
    url.searchParams.set("invitation", context.guardianship_invitation_id);
    url.hash = new URLSearchParams({ secret: invitationSecret }).toString();
    const pet = context.pet_name ?? "una mascota";
    const text =
      `Te han invitado a compartir la responsabilidad de ${pet}. Acepta la invitación: ${url.toString()}`;
    return {
      subject: `Invitación para cuidar de ${pet}`,
      text,
      html: `<p>Te han invitado a compartir la responsabilidad de <strong>${
        htmlEscape(pet)
      }</strong>.</p><p><a href="${
        htmlEscape(url.toString())
      }">Aceptar invitación</a></p>`,
    };
  }

  const pet = context.pet_name ?? "tu mascota";
  const label = APPOINTMENT_LABELS[context.communication_type];
  if (!context.appointment_id || !context.pet_id || !label) {
    throw new TypeError("Appointment context is incomplete");
  }
  const date = localizedDate(context);
  const clinic = context.clinic_name ? ` en ${context.clinic_name}` : "";
  const schedule = date ? ` para ${date}` : "";
  // petId matches the mobile appointment detail route
  // (apps/mobile/src/lib/appointments-navigation.ts), as in the push payload.
  const url = new URL(
    `/appointments/${encodeURIComponent(context.appointment_id)}`,
    publicAppUrl,
  );
  url.searchParams.set("petId", context.pet_id);
  if (context.communication_type === ALTERNATIVE_TIME_PROPOSED) {
    const proposer = context.clinic_name
      ? `La clínica ${context.clinic_name}`
      : "La clínica";
    const proposed = date ? `: ${date}` : "";
    const proposal =
      `${proposer} propone otro horario para la solicitud de cita de ${pet}${proposed}. ${NOT_YET_CONFIRMED}`;
    return {
      subject: `La clínica propone otro horario para la cita de ${pet}`,
      text: `${proposal} Puedes aceptarlo en la aplicación: ${url.toString()}`,
      html: `<p>${htmlEscape(proposal)}</p><p><a href="${
        htmlEscape(url.toString())
      }">Ver la propuesta</a></p>`,
    };
  }
  const sentence = `La cita de ${pet}${clinic} ${label}${schedule}.`;
  return {
    subject: `Actualización de la cita de ${pet}`,
    text: `${sentence} Consulta el estado actual: ${url.toString()}`,
    html: `<p>${htmlEscape(sentence)}</p><p><a href="${
      htmlEscape(url.toString())
    }">Consultar estado actual</a></p>`,
  };
}

export function renderPush(context: DeliveryContext): RenderedPush {
  if (
    !context.appointment_id || !context.pet_id ||
    !APPOINTMENT_LABELS[context.communication_type]
  ) {
    throw new TypeError(
      "Push is only supported for Appointment Communications",
    );
  }
  const pet = context.pet_name ?? "tu mascota";
  // Privacy-minimized like every Appointment push (no Clinic, no time), but
  // the alternative time must never read as a confirmed change.
  const body = context.communication_type === ALTERNATIVE_TIME_PROPOSED
    ? `La clínica propone otro horario para la solicitud de cita de ${pet}. ${NOT_YET_CONFIRMED}`
    : `Hay una actualización sobre la cita de ${pet}.`;
  return {
    title: "MenizVet",
    body,
    // pet_id lets the mobile client navigate directly to the Guardian
    // Pet-scoped Appointment-detail route without a client-side fan-out
    // lookup across every currently-guarded Pet (Milestone H). It is a
    // plain domain identifier, not a name or medical content, so it is not
    // covered by the push-content-privacy exclusion list (Appointment
    // reason, diagnosis, medical history, Clinical Attachments, Care
    // Authorization internals, recipient email, provider token) — the same
    // category as the appointment_id this payload already carried.
    // Possession of it still does not grant authorization (SPEC-COM-002
    // BR-28): the mobile route re-verifies current Guardianship itself.
    data: Object.freeze({
      route: "appointment",
      appointment_id: context.appointment_id,
      pet_id: context.pet_id,
    }),
  };
}
