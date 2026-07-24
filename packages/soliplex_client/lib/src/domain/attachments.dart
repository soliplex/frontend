/// Name of the skill whose presence enables file attachments.
///
/// The backend uses this same string as the AG-UI state namespace it seeds
/// into every thread created in a room that has the skill, so it identifies
/// attachment capability at both the room and thread level.
const sandboxSkillName = 'bubble-sandbox';
