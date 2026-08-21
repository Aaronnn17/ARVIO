(async function() {
  var params = new URLSearchParams(window.location.search);
  var code = params.get("code");
  var state = params.get("state") || params.get("session");
  var error = params.get("error");
  var errorDesc = params.get("error_description");

  var heading = document.getElementById("heading");
  var message = document.getElementById("message");
  var codeContainer = document.getElementById("code-container");
  var codeVal = document.getElementById("code-val");

  function renderSuccessLink(textPrefix, linkText) {
    message.textContent = textPrefix;
    var link = document.createElement("a");
    link.href = deepLink;
    link.style.color = "#5865F2";
    link.style.fontWeight = "600";
    link.textContent = linkText;
    message.appendChild(link);
    var dot = document.createTextNode(".");
    message.appendChild(dot);
  }

  if (error) {
    heading.textContent = "Authorization Failed";
    heading.style.color = "#ff8a76";
    message.textContent = errorDesc || error;
    return;
  }

  if (!code) {
    heading.textContent = "No Code Received";
    message.textContent = "Discord did not return a valid authorization response.";
    return;
  }

  if (codeVal) {
    codeVal.textContent = code;
  }
  var deepLink = "arvio://discord/auth?code=" + encodeURIComponent(code) + (state ? "&state=" + encodeURIComponent(state) : "");
  try {
    window.location.href = deepLink;
  } catch (e) {}

  // If we have a TV session ID / state, notify the backend
  if (state && /^[A-Za-z0-9_-]{40,128}$/.test(state)) {
    try {
      var response = await fetch("/.netlify/functions/discord-auth-callback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ device_code: state, code: code })
      });

      if (response.ok) {
        heading.textContent = "Discord Connected! 🎉";
        heading.style.color = "#6ee7a3";
        renderSuccessLink("Authorized successfully! If ARVIO did not open automatically, ", "tap here to return to ARVIO");
      } else {
        heading.textContent = "Could Not Notify TV";
        heading.style.color = "#ff8a76";
        renderSuccessLink("Authorized with Discord, but the pairing session could not be delivered to your TV. If you are on your device, ", "tap here to return to ARVIO");
      }
    } catch (e) {
      console.error(e);
      heading.textContent = "Could Not Notify TV";
      heading.style.color = "#ff8a76";
      renderSuccessLink("Authorized with Discord, but network delivery to your TV failed. If you are on your device, ", "tap here to return to ARVIO");
    }
    return;
  }

  // Direct / no-state flow (e.g. mobile deep link handoff)
  heading.textContent = "Discord Connected! 🎉";
  heading.style.color = "#6ee7a3";
  renderSuccessLink("Authorized! If ARVIO did not open automatically, ", "tap here to return to ARVIO");
})();
