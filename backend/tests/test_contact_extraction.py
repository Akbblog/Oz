from main import GoogleBusinessScraper


def test_extract_email_from_page_body():
    details = GoogleBusinessScraper._extract_contact_details_from_page(
        "<html><body>Contact us at info@example.com</body></html>",
        [],
        base_url="https://example.com",
    )
    assert details["email"] == "info@example.com"


def test_extract_email_from_mailto_link():
    details = GoogleBusinessScraper._extract_contact_details_from_page(
        "<html><body>Get in touch</body></html>",
        ["mailto:sales@example.com"],
        base_url="https://example.com",
    )
    assert details["email"] == "sales@example.com"
