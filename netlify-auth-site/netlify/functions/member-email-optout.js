// GET /member-email-optout?a=<account key>&s=<signature>
// One-click unsubscribe from ARVIO Premium member emails (tips, the yearly
// offer, pass reminders, referral news). The link is signed, so it can only
// unsubscribe the account it was sent to.
const { verifyOptout, optOut } = require("./_member-emails");

function page(statusCode, title, message) {
  return {
    statusCode,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
    body: `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title><style>body{font:16px/1.5 system-ui,sans-serif;max-width:32rem;margin:15vh auto;padding:0 16px;color:#e8e8e8;background:#101114}a{color:#7ee0c3}</style></head><body><h1>${title}</h1><p>${message}</p><p><a href="https://web.arvio.tv/">Open ARVIO Web</a></p></body></html>`
  };
}

exports.handler = async (event) => {
  if (event.httpMethod !== "GET" && event.httpMethod !== "POST") return page(405, "Not allowed", "This link only works when opened.");
  const query = event.queryStringParameters || {};
  const accountKey = String(query.a || "");
  if (!verifyOptout(accountKey, String(query.s || ""))) {
    return page(400, "Link not valid", "This unsubscribe link is incomplete or has been changed.");
  }
  try {
    await optOut(event, accountKey);
    return page(200, "You are unsubscribed", "You will no longer get ARVIO Premium member emails. Your membership is not affected.");
  } catch (error) {
    console.error("member-email-optout failed", error && error.message);
    return page(500, "Something went wrong", "Please try the link again in a minute.");
  }
};
