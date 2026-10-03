"""Screenshot hierarchy: run / application / module / flow / case / step.png."""
from pathlib import Path

LEGACY_CASES = {
    '01': 'AUTH-REG-01', '02': 'AUTH-REG-02', '03': 'AUTH-REG-03', '04': 'AUTH-REG-03',
    '05': 'AUTH-REG-03', '06': 'AUTH-LOGIN-01', '07': 'AUTH-VERIFY-01', '08': 'AUTH-REG-04',
    '09': 'AUTH-LOGIN-02', '10': 'AUTH-LOGIN-03', '11': 'AUTH-LOGIN-04', '12': 'AUTH-LOGIN-04',
    '13': 'AUTH-LOGIN-05', '14': 'AUTH-LOGIN-06', '15': 'AUTH-ADMIN-01',
    '16': 'AUTH-ADMIN-02', '17': 'AUTH-ADMIN-02', '18': 'AUTH-ADMIN-03',
}


def auth_scope(case_id):
    application = 'admin' if case_id.startswith('AUTH-ADMIN-') else 'user'
    if case_id.startswith('AUTH-REG-'):
        flow = 'registration'
    elif case_id.startswith('AUTH-VERIFY-'):
        flow = 'email_verification'
    elif case_id in ('AUTH-LOGIN-06', 'AUTH-ADMIN-03'):
        flow = 'logout'
    elif case_id == 'AUTH-ADMIN-01':
        flow = 'access_denied'
    else:
        flow = 'login'
    return application, 'authentication', flow


def auth_relative_path(case_id, filename):
    if not case_id or '/' in filename or '\\' in filename or Path(filename).name != filename:
        raise ValueError('Use a case ID and a plain screenshot filename.')
    return Path(*auth_scope(case_id), case_id, filename)


def legacy_case(filename):
    if filename.startswith('AUTH-') and filename.endswith('-failure.png'):
        return filename.removesuffix('-failure.png')
    return LEGACY_CASES.get(filename[:2])
