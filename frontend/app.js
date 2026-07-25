const endpoint = (window.APP_CONFIG?.apiEndpoint || "").replace(/\/$/, "");
const input = document.querySelector("#fileInput");
const drop = document.querySelector("#dropZone");
const status = document.querySelector("#status");
const result = document.querySelector("#result");
const progress = document.querySelector("#progress");
const bar = document.querySelector("#progressBar");

document.querySelector("#chooseButton").addEventListener("click", () => input.click());
input.addEventListener("change", () => input.files[0] && upload(input.files[0]));
["dragenter", "dragover"].forEach(name => drop.addEventListener(name, e => { e.preventDefault(); drop.classList.add("drag"); }));
["dragleave", "drop"].forEach(name => drop.addEventListener(name, e => { e.preventDefault(); drop.classList.remove("drag"); }));
drop.addEventListener("drop", e => e.dataTransfer.files[0] && upload(e.dataTransfer.files[0]));

async function upload(file) {
  result.hidden = true; progress.hidden = false; bar.style.width = "10%"; status.textContent = "Requesting secure upload…";
  try {
    if (!endpoint.startsWith("http")) throw new Error("Set apiEndpoint in frontend/config.js first.");
    if (!['image/jpeg','image/png','image/webp'].includes(file.type) || file.size > 10 * 1024 * 1024) throw new Error("Choose a JPEG, PNG, or WebP under 10 MB.");
    const signed = await fetch(`${endpoint}/uploads`, {method:"POST", headers:{"content-type":"application/json"}, body:JSON.stringify({contentType:file.type,size:file.size})});
    if (!signed.ok) throw new Error((await signed.json()).message || "Could not create upload URL");
    const {key, uploadUrl} = await signed.json();
    bar.style.width = "35%"; status.textContent = "Uploading directly to S3…";
    const stored = await fetch(uploadUrl, {method:"PUT", headers:{"content-type":file.type}, body:file});
    if (!stored.ok) throw new Error("S3 upload failed");
    bar.style.width = "70%"; status.textContent = "Lambda is processing the image…";
    for (let attempt = 0; attempt < 15; attempt++) {
      await new Promise(resolve => setTimeout(resolve, 1500));
      const check = await fetch(`${endpoint}/images/${encodeURIComponent(key)}`);
      const payload = await check.json();
      if (check.ok && payload.status === "ready") {
        result.src = payload.imageUrl; result.hidden = false; bar.style.width = "100%"; status.textContent = "Processing complete"; return;
      }
    }
    throw new Error("Processing is taking longer than expected. Check again shortly.");
  } catch (error) { status.textContent = error.message; bar.style.width = "0"; }
}

