from main import GoogleBusinessScraper


def test_parse_wa_me_link():
    details = GoogleBusinessScraper._parse_whatsapp_link(
        "https://wa.me/14155550123",
    )
    assert details["whatsapp"] == "14155550123"
    assert details["whatsapp_url"] == "https://wa.me/14155550123"


def test_parse_api_whatsapp_link_with_phone_query():
    details = GoogleBusinessScraper._parse_whatsapp_link(
        "https://api.whatsapp.com/send?phone=%2B1%20415-555-0123&text=Hello",
    )
    assert details["whatsapp"] == "+14155550123"
    assert details["whatsapp_url"] == "https://wa.me/14155550123"


def test_parse_whatsapp_scheme_link():
    details = GoogleBusinessScraper._parse_whatsapp_link(
        "whatsapp://send?phone=447911123456",
    )
    assert details["whatsapp"] == "447911123456"
    assert details["whatsapp_url"] == "https://wa.me/447911123456"


def test_invalid_whatsapp_number_rejected_but_url_kept():
    details = GoogleBusinessScraper._parse_whatsapp_link("https://wa.me/123")
    assert details["whatsapp"] == ""
    assert details["whatsapp_url"] == "https://wa.me/123"


def test_email_only_page_returns_email_without_whatsapp():
    details = GoogleBusinessScraper._extract_contact_details_from_page(
        "<html><body>Contact us at info@example.com</body></html>",
        [],
        base_url="https://example.com",
    )
    assert details["email"] == "info@example.com"
    assert details["whatsapp"] == ""
    assert details["whatsapp_url"] == ""
