/// Utility class implementing security controls for input validation and HTML sanitization.
class SecurityValidator {
  SecurityValidator._();

  /// Validates that a feed URL uses an allowed scheme and does not target internal subnets.
  ///
  /// Prevents Server-Side Request Forgery (SSRF) and local network reconnaissance.
  static bool isValidFeedUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return false;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return false;
    }

    // Reject loopback and local hostnames
    if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0' || host == '::1') {
      return false;
    }

    // Check IPv4 private and link-local subnets
    final ipV4Parts = host.split('.');
    if (ipV4Parts.length == 4) {
      final octets = ipV4Parts.map(int.tryParse).toList();
      final hasInvalidOctet = octets.any((octet) => octet == null || octet < 0 || octet > 255);
      if (!hasInvalidOctet) {
        final o1 = octets[0]!;
        final o2 = octets[1]!;

        // 10.0.0.0/8
        if (o1 == 10) return false;
        // 127.0.0.0/8
        if (o1 == 127) return false;
        // 169.254.0.0/16 (Link-local)
        if (o1 == 169 && o2 == 254) return false;
        // 172.16.0.0/12
        if (o1 == 172 && (o2 >= 16 && o2 <= 31)) return false;
        // 192.168.0.0/16
        if (o1 == 192 && o2 == 168) return false;
        // 0.0.0.0/8
        if (o1 == 0) return false;
      }
    }

    return true;
  }

  /// Sanitizes raw HTML string by removing active scripting and dangerous elements.
  static String sanitizeHtml(String rawHtml) {
    if (rawHtml.isEmpty) {
      return '';
    }

    var sanitized = rawHtml;

    // Remove dangerous tags and contents
    final dangerousTags = [
      'script',
      'iframe',
      'object',
      'embed',
      'applet',
      'meta',
      'link',
      'style',
      'form',
      'svg',
    ];

    for (final tag in dangerousTags) {
      sanitized = sanitized.replaceAll(
        RegExp('<$tag\\b[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false),
        '',
      );
      sanitized = sanitized.replaceAll(
        RegExp('<$tag\\b[^>]*/>', caseSensitive: false),
        '',
      );
      sanitized = sanitized.replaceAll(
        RegExp('<$tag\\b[^>]*>', caseSensitive: false),
        '',
      );
    }

    // Strip inline event handlers (e.g. onclick, onerror, onload)
    sanitized = sanitized.replaceAll(
      RegExp(r'''\son\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)''', caseSensitive: false),
      '',
    );

    // Strip javascript: pseudo-protocols in href and src
    sanitized = sanitized.replaceAll(
      RegExp(r'''(href|src)\s*=\s*['"]\s*javascript:[^'"]*['"]''', caseSensitive: false),
      '',
    );

    return sanitized;
  }

  /// Converts HTML content to normalized plain text.
  static String extractPlainText(String htmlString) {
    if (htmlString.isEmpty) {
      return '';
    }

    // Strip all HTML tags
    var text = htmlString.replaceAll(RegExp(r'<[^>]*>'), ' ');

    // Decode common XML/HTML entities
    text = decodeHtmlEntities(text);

    // Normalize consecutive whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Clean whitespace preceding punctuation marks
    text = text.replaceAllMapped(RegExp(r'\s+([.,!?;:])'), (m) => m.group(1)!);

    return text;
  }

  /// Decodes standard HTML entities into UTF-8 characters.
  static String decodeHtmlEntities(String text) {
    if (!text.contains('&')) {
      return text;
    }

    var decoded = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll('&rsquo;', "'")
        .replaceAll('&lsquo;', "'")
        .replaceAll('&rdquo;', '"')
        .replaceAll('&ldquo;', '"');

    // Decode numeric decimal entities (e.g., &#8217;)
    decoded = decoded.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1)!);
      if (code != null && code > 0 && code < 0x10FFFF) {
        try {
          return String.fromCharCode(code);
        } catch (_) {
          return match.group(0)!;
        }
      }
      return match.group(0)!;
    });

    // Decode numeric hexadecimal entities (e.g., &#x27;)
    decoded = decoded.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1)!, radix: 16);
      if (code != null && code > 0 && code < 0x10FFFF) {
        try {
          return String.fromCharCode(code);
        } catch (_) {
          return match.group(0)!;
        }
      }
      return match.group(0)!;
    });

    return decoded;
  }
}

