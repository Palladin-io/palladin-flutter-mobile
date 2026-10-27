package io.palladin.autofill.savefixture.form;

import android.app.Activity;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.view.autofill.AutofillManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;

public final class SaveFormActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(24, 100, 24, 24);
        EditText username = new EditText(this);
        username.setId(View.generateViewId());
        username.setHint("Synthetic username");
        username.setShowSoftInputOnFocus(false);
        username.setAutofillHints(View.AUTOFILL_HINT_USERNAME);
        username.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        EditText password = new EditText(this);
        password.setId(View.generateViewId());
        password.setHint("Synthetic password");
        password.setShowSoftInputOnFocus(false);
        password.setAutofillHints(View.AUTOFILL_HINT_PASSWORD);
        password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        layout.addView(username);
        layout.addView(password);
        Button request = new Button(this);
        request.setText("Request Autofill");
        request.setOnClickListener(view -> {
            username.requestFocus();
            getSystemService(AutofillManager.class).requestAutofill(username);
        });
        layout.addView(request);
        Button populate = new Button(this);
        populate.setText("Populate synthetic fields");
        populate.setOnClickListener(view -> {
            username.setText("synthetic-save-user");
            password.setText("synthetic-save-password-1");
        });
        layout.addView(populate);
        Button submit = new Button(this);
        submit.setText("Submit synthetic form");
        submit.setOnClickListener(view -> getSystemService(AutofillManager.class).commit());
        layout.addView(submit);
        setContentView(layout);
    }
}
