"""Name compatibility for possible matches (review only, never an automatic merge)."""
from crm.matching import name_key, names_compatible


def nc(a, b):
    return names_compatible(name_key(a), name_key(b))


def test_same_business_spellings_are_compatible():
    assert nc("Al Waab Dental Clinic LLC", "Al Waab Dental Clinic")
    assert nc("Café Bloom", "Cafe Bloom")
    assert nc("Joe's Plumbing", "Joes Plumbing & Heating")


def test_different_numbers_mean_different_branches():
    assert not nc("Seed Biz 9-0", "Seed Biz 6-0")
    assert not nc("Doha Clinic 2", "Doha Clinic 12")
    assert nc("Doha Clinic 2", "Doha Clinic 2 LLC")
    # a number on one side only stays compatible (e.g. "Clinic" vs "Clinic 2" may be the same business)
    assert nc("Doha Clinic", "Doha Clinic 2")


def test_unrelated_names_are_not_compatible():
    assert not nc("Blue Bakery", "Red Garage")
    assert not nc("", "Blue Bakery")
