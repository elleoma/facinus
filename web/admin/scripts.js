// Copy to clipboard functionality
document.addEventListener('click', function(e) {
    if (e.target && e.target.classList.contains('copy-btn')) {
        const text = e.target.getAttribute('data-clipboard');
        
        // Check for clipboard API support
        if (navigator.clipboard) {
            navigator.clipboard.writeText(text)
                .then(function() {
                    const originalText = e.target.innerText;
                    e.target.innerText = "copied!";
                    setTimeout(() => {
                        e.target.innerText = originalText;
                    }, 1000);
                })
                .catch(function(err) {
                    console.error('Failed to copy: ', err);
                    // Fallback method
                    fallbackCopyTextToClipboard(text, e.target);
                });
        } else {
            // Fallback for browsers without clipboard API
            fallbackCopyTextToClipboard(text, e.target);
        }
    }
});

// Fallback copy method for older browsers
function fallbackCopyTextToClipboard(text, button) {
    const textArea = document.createElement("textarea");
    textArea.value = text;
    textArea.style.position = "fixed";  // Avoid scrolling to bottom
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    
    try {
        const successful = document.execCommand('copy');
        if (successful) {
            const originalText = button.innerText;
            button.innerText = "copied!";
            setTimeout(() => {
                button.innerText = originalText;
            }, 1000);
        }
    } catch (err) {
        console.error('Fallback: Unable to copy', err);
    }
    
    document.body.removeChild(textArea);
}
// Search functionality
function setupSearch(inputId, itemsSelector) {
    const searchInput = document.getElementById(inputId);
    if (searchInput) {
        searchInput.addEventListener('input', function() {
            const query = this.value.toLowerCase();
            const items = document.querySelectorAll(itemsSelector);
            
            items.forEach(item => {
                const text = item.textContent.toLowerCase();
                item.parentNode.style.display = text.includes(query) ? 'block' : 'none';
            });
        });
    }
}

// Setup search functionality if elements exist
setupSearch('hostSearch', '.host-list a');
setupSearch('logSearch', '.log-list a');

// Download button functionality
const downloadBtn = document.getElementById('downloadBtn');
if (downloadBtn) {
    downloadBtn.addEventListener('click', function() {
        const logContent = document.querySelector('.logs');
        if (logContent) {
            const content = logContent.innerText;
            const blob = new Blob([content], {type: 'text/plain'});
            const url = URL.createObjectURL(blob);
            
            const a = document.createElement('a');
            a.href = url;
            const urlParams = new URLSearchParams(window.location.search);
            a.download = urlParams.get('log') || "log";
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        }
    });
}

// Refresh button functionality
const refreshBtn = document.getElementById('refreshBtn');
if (refreshBtn) {
    refreshBtn.addEventListener('click', function() {
        location.reload();
    });
}
